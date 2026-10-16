import AppKit
import Combine
import AppSwitchCore

@main
enum AppSwitchApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let permissions = PermissionState()
    private let catalog = WindowCatalog()
    private let keyboard = KeyboardController()
    private let panel = SwitcherPanel()
    private let settings = SettingsWindow()
    private var session = SwitchSession()
    private var windows: [CodeWindow] = []
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var permissionTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var isPreviewing = false
    private var generation = 0
    private let demo = CommandLine.arguments.contains("--demo")
    // Opt-in developer diagnostics contain state only, never titles or file contents.
    private var diagnosticURL: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--diagnostic-file"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        catalog.setApplications(preferences.applicationSelection.enabledBundleIDs)
        keyboard.isSwitching = { [weak self] in self?.session.isActive ?? false }
        keyboard.onAction = { [weak self] action in self?.handle(action) }
        keyboard.onHotKey = { [weak self] in
            self?.permissions.lastHotKey = Date()
            self?.writeDiagnostics()
        }
        panel.model.onSelect = { [weak self] id in
            self?.session.select(id)
            self?.commit()
        }
        panel.model.onCancel = { [weak self] in self?.cancel() }
        keyboard.shortcut = preferences.shortcut
        preferences.$shortcut.dropFirst().sink { [weak self] shortcut in
            self?.cancel()
            self?.keyboard.shortcut = shortcut
            self?.panel.model.shortcutLabel = shortcut.label
            if self?.demo == false { self?.checkPermissions(forceRetry: true) }
        }.store(in: &subscriptions)
        preferences.$applicationSelection.dropFirst().sink { [weak self] selection in
            guard let self else { return }
            self.cancel()
            ApplicationIcons.clear()
            self.catalog.setApplications(selection.enabledBundleIDs)
            self.writeDiagnostics()
        }.store(in: &subscriptions)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.session.isActive, !self.panel.containsMouse else { return }
            self.cancel()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.session.isActive, !self.panel.containsMouse { self.cancel() }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.session.isActive, self.isPreviewing, !self.keyboard.isRunning else { return event }
            switch event.keyCode {
            case 53: self.cancel()
            case 36, 76: self.commit()
            case 48: self.handle(.move(event.modifierFlags.contains(.shift) ? -1 : 1))
            case 125, 124: self.handle(.move(1))
            case 126, 123: self.handle(.move(-1))
            default: return event
            }
            return nil
        }
        if demo {
            showDemo()
            return
        }
        checkPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
        if !permissions.accessibility || CommandLine.arguments.contains("--settings") { showSettings() }
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "AppSwitch")
        item.button?.toolTip = "AppSwitch — 应用窗口切换"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AppSwitch", action: nil, keyEquivalent: ""))
        let status = NSMenuItem(title: "正在检查权限…", action: nil, keyEquivalent: "")
        menu.addItem(status)
        statusLine = status
        menu.addItem(.separator())
        let show = NSMenuItem(title: "显示窗口列表", action: #selector(showFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let settingsItem = NSMenuItem(title: "设置与权限…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 AppSwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item

        // Supply normal app/edit menu shortcuts while the settings window is active.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "AppSwitch")
        let preferencesItem = NSMenuItem(title: "AppSwitch 设置…", action: #selector(showSettings), keyEquivalent: ",")
        preferencesItem.target = self
        applicationMenu.addItem(preferencesItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(NSMenuItem(title: "退出 AppSwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func checkPermissions(forceRetry: Bool = false) {
        let trusted = AXIsProcessTrusted()
        let wasTrusted = permissions.accessibility
        let newlyTrusted = trusted && !permissions.accessibility
        permissions.accessibility = trusted
        // Registration must work even when window-control permission is missing.
        if forceRetry || (!keyboard.isRunning && permissions.note == nil) {
            let ready = keyboard.start()
            permissions.note = ready ? nil : "快捷键注册失败（系统错误 \(keyboard.lastError)）。可能被其他应用占用，请换一个快捷键后重新检查。"
        }
        if trusted {
            catalog.startObserving()
            if newlyTrusted && keyboard.isRunning { permissions.note = nil }
        } else {
            if wasTrusted && session.isActive && !isPreviewing { cancel() }
        }
        permissions.keyboard = keyboard.isRunning
        statusLine?.title = permissions.keyboard ? "\(preferences.shortcut.label) · \(trusted ? "已就绪" : "等待窗口控制授权")" : "快捷键注册失败，请查看设置"
        writeDiagnostics()
    }

    private func writeDiagnostics() {
        guard let url = diagnosticURL else { return }
        let state: [String: Any] = [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "runningPath": Bundle.main.bundleURL.path,
            "processID": ProcessInfo.processInfo.processIdentifier,
            "accessibilityGranted": permissions.accessibility,
            "hotKeyRegistered": keyboard.isRunning,
            "hotKeyError": keyboard.lastError,
            "shortcut": preferences.shortcut.label,
            "lastHotKey": permissions.lastHotKey.map { ISO8601DateFormatter().string(from: $0) } ?? "never",
            "switcherActive": session.isActive,
            "loadedWindowCount": windows.count,
            "discoveryCounts": catalog.discoveryCounts,
            "windowOrdering": "fixed",
            "windowOrder": catalog.orderedWindowIDs.map(\.uuidString),
            "trackedApplicationCount": preferences.applicationSelection.applications.count,
            "enabledApplicationCount": preferences.applicationSelection.enabledBundleIDs.count,
            "note": permissions.note ?? "",
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @objc private func showSettings() {
        settings.show(permissions: permissions, preferences: preferences, onEnable: { [weak self] in
            guard self != nil else { return }
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }, onPreview: { [weak self] in self?.showFromMenu() }, onDemo: { [weak self] in
            self?.showDemo()
        }, onRetry: { [weak self] in
            self?.checkPermissions(forceRetry: true)
        })
    }

    @objc private func showFromMenu() {
        if demo { showDemo(); return }
        guard AXIsProcessTrusted() else { showSettings(); return }
        DispatchQueue.main.async { [weak self] in
            self?.begin(direction: 1)
            self?.keyboard.usePersistentSelection()
        }
    }

    private func handle(_ action: SwitchKeyAction) {
        switch action {
        case .begin(let direction): begin(direction: direction)
        case .move(let direction):
            session.move(direction)
            panel.model.selectedID = session.selectedID
        case .commit: commit()
        case .cancel: cancel()
        }
    }

    private func begin(direction: Int) {
        guard AXIsProcessTrusted() else { showSettings(); return }
        isPreviewing = false
        generation += 1
        let request = generation
        session.begin(direction: direction)
        windows = []
        panel.model.rows = []
        panel.model.selectedID = nil
        panel.model.message = nil
        panel.model.loading = true
        panel.model.shortcutLabel = preferences.shortcut.label
        let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        panel.show(acceptsKeyboardFocus: true)
        catalog.refresh(focusedApplicationPID: sourcePID) { [weak self] snapshot in
            guard let self, self.session.isActive, self.generation == request else { return }
            self.windows = snapshot.windows
            self.session.load(ids: snapshot.windows.map(\.id), focusedID: snapshot.focusedID,
                              preferredID: snapshot.preferredID)
            self.panel.model.rows = snapshot.windows.map { WindowRow(window: $0, mode: self.preferences.titleMode) }
            self.panel.model.selectedID = self.session.selectedID
            self.panel.model.loading = false
            if !snapshot.failedApplications.isEmpty {
                self.panel.model.message = "部分窗口未能读取，请检查权限或稍后重试。"
            }
            self.panel.resize()
            if self.session.commitWhenReady { self.commit() }
        }
    }

    private func commit() {
        guard session.isActive else { return }
        if isPreviewing { cancel(); return }
        if session.isLoading { session.requestCommit(); return }
        guard let id = session.selectedID, let target = windows.first(where: { $0.id == id }) else {
            // Leave the empty state visible so the user can understand why nothing switched.
            return
        }
        cancel()
        catalog.focus(target) { [weak self] error in
            guard let self, let error else { return }
            self.permissions.note = error
            self.showSettings()
        }
    }

    private func cancel() {
        generation += 1
        session.cancel()
        keyboard.usePersistentSelection()
        panel.hide()
        windows = []
        isPreviewing = false
    }

    private func showDemo() {
        generation += 1
        windows = []
        isPreviewing = true
        keyboard.usePersistentSelection()
        let rows = [WindowRow(project: "AppSwitch", title: "App.swift — AppSwitch"),
                    WindowRow(project: "backend-api", title: "main.go — backend-api [SSH: dev-server]"),
                    WindowRow(project: "Apple Developer", title: "Apple Developer", applicationName: "Safari",
                              bundleIdentifier: "com.apple.Safari"),
                    WindowRow(project: "zsh — AppSwitch", title: "zsh — AppSwitch", badge: "已最小化",
                              applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")]
        session.begin(direction: 1)
        session.load(ids: rows.map(\.id), focusedID: nil)
        session.move(1)
        panel.model.rows = rows
        panel.model.selectedID = session.selectedID
        panel.model.loading = false
        panel.model.message = "界面演示 · 示例数据，不会切换真实窗口"
        panel.show(acceptsKeyboardFocus: true, activateApplication: true)
        if demo { statusLine?.title = "界面演示模式" }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboard.stop()
        permissionTimer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }
}
