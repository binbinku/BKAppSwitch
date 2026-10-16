import AppKit
import SwiftUI
import AppSwitchCore

final class PermissionState: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var keyboard = false
    @Published var note: String?
    @Published var lastHotKey: Date?
}

private struct SettingsView: View {
    @ObservedObject var permissions: PermissionState
    @ObservedObject var preferences: Preferences
    let onEnable: () -> Void
    let onPreview: () -> Void
    let onDemo: () -> Void
    let onRetry: () -> Void

    private let titleSetting = "\"window.title\": \"${rootName}${separator}${activeEditorShort}\""

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 21) {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 32)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AppSwitch").font(.system(size: 26, weight: .bold))
                    Text("选择你的应用，快速切换它们的窗口。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            applicationSettings
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(permissions.accessibility ? "辅助功能：已授权" : "辅助功能：未授权", systemImage: permissions.accessibility ? "checkmark.circle.fill" : "lock.circle")
                            .foregroundStyle(permissions.accessibility ? .green : .orange)
                        Spacer()
                        Button(permissions.accessibility ? "打开权限设置" : "授权辅助功能", action: onEnable)
                    }
                    Text("辅助功能用于读取标题和切换窗口。快捷键唤起独立注册，不依赖此权限，也不需要「输入监控」。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Label(permissions.keyboard ? "系统热键：已注册" : "系统热键：注册失败",
                              systemImage: permissions.keyboard ? "keyboard.badge.ellipsis" : "keyboard")
                        Spacer()
                        Button("重新检查", action: onRetry)
                    }
                    HStack {
                        Text("最近快捷键触发：")
                        if let date = permissions.lastHotKey { Text(date, style: .time) }
                        else { Text("尚未触发，按一次上方快捷键测试") }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    if let note = permissions.note {
                        Text(note).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(9)
            } label: { Text("首次使用").font(.system(size: 12, weight: .medium)) }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前运行的应用").font(.system(size: 12, weight: .semibold))
                    Text(Bundle.main.bundleURL.path).font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if !permissions.accessibility {
                        Text("若系统中的 AppSwitch 开关已打开，这里仍显示未授权：在辅助功能列表中用「−」移除旧的 AppSwitch，再用「+」添加上方路径的当前应用并开启权限，最后退出并重新打开 AppSwitch。")
                            .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("本地临时签名：重新编译后需要重新授权。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                }.padding(9)
            }

            VStack(alignment: .leading, spacing: 13) {
                Text("窗口范围：所有桌面").font(.system(size: 12, weight: .medium))
                Text("固定窗口顺序；新窗口排到末尾。默认选中最近使用的窗口，不移动列表位置。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("切换快捷键", selection: $preferences.shortcut) {
                    ForEach(Shortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("VS Code 标题识别", selection: $preferences.titleMode) {
                    ForEach(TitleMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("按住 ⌥，连续按快捷键选择；松开 ⌥ 确认。Shift 反向，方向键选择，Esc 取消。也可直接点击窗口。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("在 VS Code 用户 settings.json 中加入以下配置，让项目名显示在最前面；随后将上方识别方式设为「项目名在前」。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(titleSetting).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                    HStack {
                        Text("自动识别是启发式判断；完整原始标题始终保留。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("复制配置") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(titleSetting, forType: .string)
                        }
                    }
                }.padding(9)
            } label: { Text("更清楚的项目名").font(.system(size: 12, weight: .medium)) }

            HStack {
                Text("本地运行 · 无网络请求 · 不读取文件内容")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("界面预览", action: onDemo)
                Button("打开窗口列表", action: onPreview).buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(!permissions.accessibility)
            }
        }.padding(27)
        }.frame(width: 640, height: 690)
    }

    private var applicationSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(preferences.applicationSelection.enabledBundleIDs.count) 个应用已启用")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button { preferences.chooseApplications() } label: {
                        Label("添加应用…", systemImage: "plus")
                    }.help("从应用程序中选择一个或多个 .app")
                }
                if preferences.applicationSelection.applications.isEmpty {
                    Text("尚未添加应用。点击「添加应用」选择要切换的应用。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(preferences.applicationSelection.applications) { application in
                                HStack(spacing: 11) {
                                    Image(nsImage: ApplicationIcons.icon(bundleIdentifier: application.id, path: application.path))
                                        .renderingMode(.original).resizable().interpolation(.high).scaledToFit().frame(width: 32, height: 32)
                                        .opacity(application.isEnabled ? 1 : 0.45).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(application.name).font(.system(size: 13, weight: .medium))
                                        Text(application.path).font(.system(size: 10)).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Toggle("显示 \(application.name) 的窗口", isOn: Binding(
                                        get: { preferences.applicationSelection.applications.first { $0.id == application.id }?.isEnabled ?? false },
                                        set: { preferences.setApplicationEnabled($0, id: application.id) }
                                    )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    Button { preferences.removeApplication(application.id) } label: {
                                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                                    }.buttonStyle(.plain).help("移除 \(application.name)")
                                        .accessibilityLabel("移除 \(application.name)")
                                }.padding(.vertical, 10).padding(.horizontal, 5)
                                    .help(application.path)
                            }
                        }
                    }.frame(height: CGFloat(min(preferences.applicationSelection.applications.count, 4)) * 58)
                }
                Text("只显示已启用、正在运行的应用窗口。添加相同应用会更新路径，不会重复添加。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = preferences.applicationError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(9)
        } label: { Text("参与切换的应用").font(.system(size: 12, weight: .medium)) }
    }
}

final class SettingsWindow {
    private var window: NSWindow?

    func show(permissions: PermissionState, preferences: Preferences, onEnable: @escaping () -> Void,
              onPreview: @escaping () -> Void, onDemo: @escaping () -> Void, onRetry: @escaping () -> Void) {
        if window == nil {
            let view = SettingsView(permissions: permissions, preferences: preferences,
                                    onEnable: onEnable, onPreview: onPreview, onDemo: onDemo, onRetry: onRetry)
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "AppSwitch 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
