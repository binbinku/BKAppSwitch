import AppKit
import AppSwitchCore
import UniformTypeIdentifiers

enum Shortcut: String, CaseIterable {
    case optionTab, controlOptionTab, optionSpace

    var label: String {
        switch self {
        case .optionTab: return "⌥ Tab"
        case .controlOptionTab: return "⌃ ⌥ Tab"
        case .optionSpace: return "⌥ Space"
        }
    }
    var keyCode: Int64 { self == .optionSpace ? 49 : 48 }
}

final class Preferences: ObservableObject {
    @Published private(set) var applicationSelection: ApplicationSelection {
        didSet {
            if let data = try? JSONEncoder().encode(applicationSelection) {
                UserDefaults.standard.set(data, forKey: "applicationSelection")
            }
        }
    }
    @Published var applicationError: String?
    @Published var titleMode: TitleMode {
        didSet { UserDefaults.standard.set(titleMode.rawValue, forKey: "titleMode") }
    }
    @Published var shortcut: Shortcut {
        didSet { UserDefaults.standard.set(shortcut.rawValue, forKey: "shortcut") }
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "applicationSelection"),
           let saved = try? JSONDecoder().decode(ApplicationSelection.self, from: data) {
            applicationSelection = saved
        } else {
            let defaults = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss"]
                .compactMap { id -> TrackedApplication? in
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
                    return TrackedApplication(bundleIdentifier: id, name: url.deletingPathExtension().lastPathComponent, path: url.path)
                }
            applicationSelection = ApplicationSelection(defaults.isEmpty ? [
                TrackedApplication(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app")
            ] : defaults)
        }
        titleMode = TitleMode(rawValue: UserDefaults.standard.string(forKey: "titleMode") ?? "") ?? .automatic
        shortcut = Shortcut(rawValue: UserDefaults.standard.string(forKey: "shortcut") ?? "") ?? .optionTab
    }

    func setApplicationEnabled(_ enabled: Bool, id: String) {
        applicationSelection.setEnabled(enabled, for: id)
    }

    func removeApplication(_ id: String) { applicationSelection.remove(id) }

    func chooseApplications() {
        applicationError = nil
        let panel = NSOpenPanel()
        panel.title = "添加切换应用"
        panel.message = "选择要显示在窗口列表中的应用，可以一次选择多个。"
        panel.prompt = "添加"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            var errors: [String] = []
            var selection = self.applicationSelection
            for selected in panel.urls {
                let url = selected.resolvingSymlinksInPath().standardizedFileURL
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty,
                      bundle.executableURL != nil else {
                    errors.append("\(url.lastPathComponent) 不是可识别的应用。")
                    continue
                }
                guard id != Bundle.main.bundleIdentifier else {
                    errors.append("AppSwitch 本身无需加入切换列表。")
                    continue
                }
                selection.add(TrackedApplication(bundleIdentifier: id,
                    name: url.deletingPathExtension().lastPathComponent, path: url.path))
            }
            self.applicationSelection = selection
            self.applicationError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
