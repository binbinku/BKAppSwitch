import AppKit
import ApplicationServices
import AppSwitchCore

struct CodeWindow: Identifiable {
    let id: UUID
    let pid: pid_t
    let element: AXUIElement?
    let title: String
    let applicationName: String
    let applicationBundleIdentifier: String
    let applicationURL: URL?
    let isMinimized: Bool
    let menuItem: AXUIElement?

    init(id: UUID, pid: pid_t, element: AXUIElement? = nil, title: String, applicationName: String,
         applicationBundleIdentifier: String, applicationURL: URL?,
         isMinimized: Bool = false, menuItem: AXUIElement? = nil) {
        self.id = id
        self.pid = pid
        self.element = element
        self.title = title
        self.applicationName = applicationName
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationURL = applicationURL
        self.isMinimized = isMinimized
        self.menuItem = menuItem
    }
}

struct WindowSnapshot {
    let windows: [CodeWindow]
    let focusedID: UUID?
    let failedApplications: [String]
    let preferredID: UUID?

    init(windows: [CodeWindow], focusedID: UUID?, failedApplications: [String], preferredID: UUID? = nil) {
        self.windows = windows
        self.focusedID = focusedID
        self.failedApplications = failedApplications
        self.preferredID = preferredID
    }
}

private struct CodeApplication {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String
    let bundleURL: URL?
}

private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

private struct WindowMenuEntry {
    let element: AXUIElement
    let title: String
    let isCurrent: Bool
}

private func windowMenuEntries(_ application: AXUIElement) -> [WindowMenuEntry] {
    guard let bar = axValue(application, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
    let menuBar = bar as! AXUIElement
    let topLevel = axValue(menuBar, kAXChildrenAttribute) as? [AXUIElement] ?? []
    // Window is usually next to Help. Identify native window entries by their
    // AppKit action identifier, never a localized title or a menu position.
    for top in topLevel.reversed() {
        let menus = axValue(top, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for menu in menus {
            guard axValue(menu, kAXRoleAttribute) as? String == kAXMenuRole else { continue }
            let items = axValue(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let entries = items.compactMap { item -> WindowMenuEntry? in
                guard axValue(item, kAXIdentifierAttribute) as? String == "makeKeyAndOrderFront:",
                      axValue(item, kAXEnabledAttribute) as? Bool != false,
                      let title = axValue(item, kAXTitleAttribute) as? String, !title.isEmpty else { return nil }
                let mark = axValue(item, kAXMenuItemMarkCharAttribute) as? String ?? ""
                return WindowMenuEntry(element: item, title: title,
                                       isCurrent: mark.contains("✓") || mark.contains("✔"))
            }
            if !entries.isEmpty { return entries }
        }
    }
    return []
}

final class WindowCatalog {
    private var trackedBundleIDs: Set<String> = []
    private var configurationRevision = 0
    private let queue = DispatchQueue(label: "BKAppSwitch.accessibility", qos: .userInitiated)
    // All fields except queue-confined `knownWindows` are used on the main thread.
    private var knownWindows: [CodeWindow] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var recency: [UUID: UInt64] = [:]
    private var windowOrder = StableWindowOrder()
    private var clock: UInt64 = 0
    private var observing = false
    private(set) var discoveryCounts: [String: Int] = [:]
    var orderedWindowIDs: [UUID] { windowOrder.ids }

    func setApplications(_ bundleIDs: Set<String>) {
        guard bundleIDs != trackedBundleIDs else { return }
        trackedBundleIDs = bundleIDs
        configurationRevision += 1
        queue.async { [self] in
            knownWindows.removeAll { !bundleIDs.contains($0.applicationBundleIdentifier) }
        }
        if observing {
            refreshObservers()
            refresh { _ in }
        }
    }

    func startObserving() {
        guard !observing else { return }
        observing = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshObservers()
                self?.refresh { _ in }
            })
        }
        refreshObservers()
        refresh { _ in }
    }

    private func applications() -> [CodeApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, trackedBundleIDs.contains(id), !app.isTerminated else { return nil }
            return CodeApplication(pid: app.processIdentifier, name: app.localizedName ?? id,
                                   bundleIdentifier: id, bundleURL: app.bundleURL)
        }.sorted { $0.pid < $1.pid }
    }

    private func refreshObservers() {
        let apps = applications()
        let pids = Set(apps.map(\.pid))
        for pid in Array(observers.keys) where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
        for app in apps where observers[app.pid] == nil {
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, _, _, context in
                guard let context else { return }
                let catalog = Unmanaged<WindowCatalog>.fromOpaque(context).takeUnretainedValue()
                catalog.refresh { _ in }
            }
            guard AXObserverCreate(app.pid, callback, &observer) == .success, let observer else { continue }
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.3)
            let context = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
                AXObserverAddNotification(observer, element, notification as CFString, context)
            }
            observers[app.pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func refresh(focusedApplicationPID: pid_t? = nil, completion: @escaping (WindowSnapshot) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(WindowSnapshot(windows: [], focusedID: nil, failedApplications: ["需要辅助功能权限"]))
            return
        }
        let apps = applications()
        let revision = configurationRevision
        let frontmostPID = focusedApplicationPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [self] in
            var result: [CodeWindow] = []
            var focusedID: UUID?
            var failed: [String] = []
            var axCount = 0
            var menuCount = 0
            var retainedCount = 0
            for app in apps {
                let application = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(application, 0.3)
                let rawWindows = axValue(application, kAXWindowsAttribute) as? [AXUIElement]
                let menuEntries = windowMenuEntries(application)
                if rawWindows == nil && menuEntries.isEmpty {
                    failed.append(app.name)
                    // A failed read is not a window close. Keep this running
                    // application's last snapshot until a scan succeeds.
                    let cached = knownWindows.filter { $0.pid == app.pid }
                    result.append(contentsOf: cached)
                    retainedCount += cached.count
                    continue
                }
                let focused = app.pid == frontmostPID ? axValue(application, kAXFocusedWindowAttribute) : nil
                var visible: [CodeWindow] = []
                for element in rawWindows ?? [] {
                    AXUIElementSetMessagingTimeout(element, 0.2)
                    let role = axValue(element, kAXRoleAttribute) as? String
                    let subrole = axValue(element, kAXSubroleAttribute) as? String
                    guard role == kAXWindowRole, subrole == nil || subrole == kAXStandardWindowSubrole else { continue }
                    let title = axValue(element, kAXTitleAttribute) as? String ?? ""
                    let id = knownWindows.first {
                        $0.pid == app.pid && $0.element.map { CFEqual($0, element) } == true
                    }?.id ?? UUID()
                    let minimized = axValue(element, kAXMinimizedAttribute) as? Bool ?? false
                    visible.append(CodeWindow(id: id, pid: app.pid, element: element, title: title,
                                              applicationName: app.name, applicationBundleIdentifier: app.bundleIdentifier,
                                              applicationURL: app.bundleURL, isMinimized: minimized))
                }
                axCount += visible.count
                menuCount += menuEntries.count
                var applicationWindows: [CodeWindow] = []
                if !menuEntries.isEmpty {
                    // The native Window menu includes windows on other Spaces,
                    // even when AXWindows only exposes the visible subset.
                    let matches = WindowMenuMatcher.uniqueMatches(menuTitles: menuEntries.map(\.title),
                                                                 windowTitles: visible.map(\.title))
                    let previousWindows = knownWindows.filter { $0.pid == app.pid }
                    var strongMatches: [Int: UUID] = [:]
                    for (index, entry) in menuEntries.enumerated() {
                        if let previous = previousWindows.first(where: {
                            $0.menuItem.map { CFEqual($0, entry.element) } == true
                        }) {
                            strongMatches[index] = previous.id
                        } else if let directIndex = matches[index],
                                  previousWindows.contains(where: { $0.id == visible[directIndex].id }) {
                            strongMatches[index] = visible[directIndex].id
                        }
                    }
                    let stableIDs = WindowMenuMatcher.stableIDs(menuTitles: menuEntries.map(\.title),
                        previousTitles: previousWindows.map(\.title), previousIDs: previousWindows.map(\.id),
                        strongMatches: strongMatches)
                    for (index, entry) in menuEntries.enumerated() {
                        let direct = matches[index].map { visible[$0] }
                        // AppKit may recreate all menu objects after a focus or
                        // title update. Recover the existing identity by the AX
                        // window first, then by a title unique on both sides.
                        // Never associate duplicate titles by their list position.
                        let id = stableIDs[index] ?? direct?.id ?? UUID()
                        let previous = previousWindows.first { $0.id == id }
                        let window = CodeWindow(id: id, pid: app.pid,
                                                element: direct?.element ?? previous?.element, title: entry.title,
                                                applicationName: app.name, applicationBundleIdentifier: app.bundleIdentifier,
                                                applicationURL: app.bundleURL, isMinimized: direct?.isMinimized ?? false,
                                                menuItem: entry.element)
                        applicationWindows.append(window)
                        if app.pid == frontmostPID && (entry.isCurrent ||
                            (focused != nil && window.element.map { CFEqual(focused!, $0) } == true)) {
                            focusedID = window.id
                        }
                    }
                    // Keep AX windows that do not appear in a transiently stale menu.
                    let menuTitles = Set(menuEntries.map(\.title))
                    applicationWindows.append(contentsOf: visible.filter { !menuTitles.contains($0.title) })
                } else {
                    applicationWindows = visible
                    // Some apps temporarily hide their menu tree. A window's
                    // absence from AXWindows alone is not evidence that it closed.
                    for old in knownWindows where old.pid == app.pid {
                        guard let element = old.element,
                              !visible.contains(where: { $0.element.map { CFEqual($0, element) } == true }),
                              axValue(element, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
                        applicationWindows.append(CodeWindow(id: old.id, pid: old.pid, element: element,
                            title: axValue(element, kAXTitleAttribute) as? String ?? old.title,
                            applicationName: old.applicationName,
                            applicationBundleIdentifier: old.applicationBundleIdentifier, applicationURL: old.applicationURL,
                            isMinimized: axValue(element, kAXMinimizedAttribute) as? Bool ?? old.isMinimized))
                        retainedCount += 1
                    }
                }
                if let focused, let current = applicationWindows.first(where: {
                    $0.element.map { CFEqual($0, focused) } == true
                }) { focusedID = current.id }
                result.append(contentsOf: applicationWindows)
            }
            knownWindows = result
            let scanned = result
            let scannedFocus = focusedID
            let scannedFailures = failed
            let counts = ["accessibilityWindows": axCount, "windowMenuEntries": menuCount,
                          "retainedWindows": retainedCount, "totalWindows": result.count]
            DispatchQueue.main.async { [self] in
                guard revision == configurationRevision else { return }
                discoveryCounts = counts
                if let scannedFocus { markUsed(scannedFocus) }
                let liveIDs = Set(scanned.map(\.id))
                recency = recency.filter { liveIDs.contains($0.key) }
                let byID = Dictionary(scanned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let ordered = windowOrder.reconcile(scanned.map(\.id)).compactMap { byID[$0] }
                // History affects the initial highlight only, never row positions.
                let preferred = ordered.filter { $0.id != scannedFocus && (recency[$0.id] ?? 0) > 0 }
                    .max { (recency[$0.id] ?? 0) < (recency[$1.id] ?? 0) }?.id
                completion(WindowSnapshot(windows: ordered, focusedID: scannedFocus,
                                          failedApplications: scannedFailures, preferredID: preferred))
            }
        }
    }

    func markUsed(_ id: UUID) {
        clock += 1
        recency[id] = clock
    }

    func focus(_ window: CodeWindow, completion: @escaping (String?) -> Void) {
        // Prefer the exact native Window menu item. AppKit handles restoring the
        // window and switching to its Space, without private Space APIs.
        queue.async {
            guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
                DispatchQueue.main.async { completion("这个窗口已经关闭，请重新打开切换列表。") }
                return
            }
            if let item = window.menuItem {
                self.focusUsingMenu(window, item: item, app: app, completion: completion)
                return
            }
            guard let element = window.element,
                  axValue(element, kAXRoleAttribute) as? String == kAXWindowRole else {
                DispatchQueue.main.async { completion("这个窗口已经关闭，请重新打开切换列表。") }
                return
            }
            self.focusDirect(window, element: element, app: app, completion: completion)
        }
    }

    private func focusDirect(_ window: CodeWindow, element: AXUIElement, app: NSRunningApplication,
                             completion: @escaping (String?) -> Void) {
            guard axValue(element, kAXRoleAttribute) as? String == kAXWindowRole else {
                DispatchQueue.main.async { completion("这个窗口已经关闭，请重新打开切换列表。") }
                return
            }
            if axValue(element, kAXMinimizedAttribute) as? Bool == true {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            // Set the target main window before activation to avoid activating a sibling window.
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            DispatchQueue.main.async {
                app.unhide()
                app.activate(options: [.activateIgnoringOtherApps])
                self.queue.asyncAfter(deadline: .now() + 0.1) {
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    let application = AXUIElementCreateApplication(window.pid)
                    AXUIElementSetMessagingTimeout(application, 0.3)
                    AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, element)
                    self.verifyFocus(window, menu: nil, title: window.title, uniqueTitle: false,
                                     attempts: 12, completion: completion)
                }
            }
    }

    private func focusUsingMenu(_ window: CodeWindow, item: AXUIElement, app: NSRunningApplication,
                                completion: @escaping (String?) -> Void) {
        let application = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        let entries = windowMenuEntries(application)
        let sameTitle = entries.filter { $0.title == window.title }
        // Menu trees can be recreated. Resolve by object identity first; use a
        // title only if it uniquely identifies one live entry. Never pick the
        // first of two identically named windows.
        let entry = entries.first { CFEqual($0.element, item) } ?? (sameTitle.count == 1 ? sameTitle.first : nil)
        guard let entry else {
            if let element = window.element {
                focusDirect(window, element: element, app: app, completion: completion)
            } else {
                DispatchQueue.main.async { completion("窗口列表已发生变化，请重新打开切换列表。") }
            }
            return
        }
        let uniqueTitle = entries.filter { $0.title == entry.title }.count == 1
        DispatchQueue.main.async {
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps])
            self.queue.asyncAfter(deadline: .now() + 0.05) {
                let error = AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
                if error == .success {
                    self.queue.asyncAfter(deadline: .now() + 0.1) {
                        self.verifyFocus(window, menu: entry.element, title: entry.title, uniqueTitle: uniqueTitle,
                                         attempts: 12, completion: completion)
                    }
                } else if let element = window.element {
                    self.focusDirect(window, element: element, app: app, completion: completion)
                } else {
                    DispatchQueue.main.async { completion("未能选择目标窗口，请重新打开列表后重试。") }
                }
            }
        }
    }

    private func verifyFocus(_ window: CodeWindow, menu: AXUIElement?, title: String, uniqueTitle: Bool,
                             attempts: Int, completion: @escaping (String?) -> Void) {
        let application = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let focused = axValue(application, kAXFocusedWindowAttribute)
        let sameWindow = window.element.map { element in focused.map { CFEqual($0, element) } ?? false } ?? false
        var sameTitle = false
        if uniqueTitle, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            sameTitle = axValue(focused as! AXUIElement, kAXTitleAttribute) as? String == title
        }
        let mark = menu.flatMap { axValue($0, kAXMenuItemMarkCharAttribute) as? String } ?? ""
        let marked = focused != nil && (mark.contains("✓") || mark.contains("✔"))
        if sameWindow || sameTitle || marked {
            DispatchQueue.main.async {
                self.markUsed(window.id)
                completion(nil)
            }
        } else if attempts > 0 {
            // A Space transition is asynchronous and can take longer than a
            // same-desktop focus change. Wait without blocking the main thread.
            queue.asyncAfter(deadline: .now() + 0.12) {
                self.verifyFocus(window, menu: menu, title: title, uniqueTitle: uniqueTitle,
                                 attempts: attempts - 1, completion: completion)
            }
        } else {
            DispatchQueue.main.async { completion("macOS 尚未确认目标窗口。请检查窗口是否仍打开，以及系统的桌面切换设置。") }
        }
    }

    deinit {
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
