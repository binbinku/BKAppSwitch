import AppKit
import SwiftUI
import AppSwitchCore

struct WindowRow: Identifiable {
    let id: UUID
    let project: String
    let title: String
    let badge: String?
    let applicationName: String
    let icon: NSImage

    var subtitle: String { project == title ? applicationName : "\(applicationName) · \(title)" }

    init(window: CodeWindow, mode: TitleMode) {
        id = window.id
        let isVSCode = TrackedApplication.vscodeBundleIDs.contains(window.applicationBundleIdentifier)
        let parsed = WindowTitle(window.title, mode: isVSCode ? mode : .original)
        project = parsed.project
        title = parsed.original.isEmpty ? window.applicationName : parsed.original
        badge = window.isMinimized ? "已最小化" : (window.applicationName.contains("Insiders") ? "Insiders" : nil)
        applicationName = window.applicationName
        icon = ApplicationIcons.icon(bundleIdentifier: window.applicationBundleIdentifier, path: window.applicationURL?.path)
    }

    init(project: String, title: String, badge: String? = nil, applicationName: String = "Visual Studio Code",
         bundleIdentifier: String = "com.microsoft.VSCode") {
        id = UUID()
        self.project = project
        self.title = title
        self.badge = badge
        self.applicationName = applicationName
        icon = ApplicationIcons.icon(bundleIdentifier: bundleIdentifier)
    }
}

final class SwitcherViewModel: ObservableObject {
    @Published var rows: [WindowRow] = []
    @Published var selectedID: UUID?
    @Published var loading = true
    @Published var message: String?
    @Published var shortcutLabel = "⌥ Tab"
    var onSelect: ((UUID) -> Void)?
    var onCancel: (() -> Void)?
}

private struct SwitcherView: View {
    @ObservedObject var model: SwitcherViewModel
    private let accent = Color(red: 0.28, green: 0.85, blue: 0.74)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 19, weight: .semibold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AppSwitch").font(.system(size: 17, weight: .semibold))
                    Text("你的窗口，随手切换").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.rows.count) 个窗口").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Button { model.onCancel?() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.system(size: 17))
                }.buttonStyle(.plain).help("取消切换（Esc）").accessibilityLabel("取消切换")
            }.padding(.horizontal, 23).padding(.top, 21).padding(.bottom, 17)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 22)

            if model.loading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在读取应用窗口…").font(.system(size: 13)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 160)
            } else if model.rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "macwindow").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("没有可切换的窗口").font(.system(size: 15, weight: .medium))
                    Text(model.message ?? "在设置中添加并启用应用，然后打开对应应用的窗口。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(25).frame(maxWidth: .infinity).frame(height: 170)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                                rowView(row, index: index).id(row.id)
                            }
                        }.padding(12)
                    }
                    .frame(height: CGFloat(min(model.rows.count, 6)) * 76 + 24)
                    .onChange(of: model.selectedID) { id in
                        if let id { proxy.scrollTo(id) }
                    }
                    .onAppear { if let id = model.selectedID { proxy.scrollTo(id) } }
                }
            }
            if let message = model.message, !model.rows.isEmpty {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 22).padding(.bottom, 10)
            }
            HStack(spacing: 6) {
                Text(model.shortcutLabel).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                Text("切换").font(.system(size: 11))
                Spacer()
                Text("松开 ⌥ 确认  ·  Esc 取消").font(.system(size: 11))
            }.foregroundStyle(.secondary).padding(.horizontal, 23).padding(.top, 11).padding(.bottom, 17)
                .background(.black.opacity(0.12))
        }
        .frame(width: 560)
        .background(Color(red: 0.065, green: 0.080, blue: 0.105).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.13), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private func rowView(_ row: WindowRow, index: Int) -> some View {
        let selected = row.id == model.selectedID
        return Button { model.onSelect?(row.id) } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(selected ? accent.opacity(0.17) : .white.opacity(0.05))
                    Image(nsImage: row.icon).renderingMode(.original).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 36, height: 36).accessibilityHidden(true)
                }.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(row.project).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        if let badge = row.badge {
                            Text(badge).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(row.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 5)
                if selected {
                    Image(systemName: "arrow.turn.down.left").font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
                } else {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 13).frame(height: 71).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? accent.opacity(0.38) : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(row.title)
            .accessibilityLabel("\(row.applicationName)，\(row.project)，\(row.title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private final class NonactivatingPanel: NSPanel {
    var acceptsKeyboardFocus = false
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}

final class SwitcherPanel {
    let model = SwitcherViewModel()
    private let panel: NonactivatingPanel
    private var hosting: NSHostingView<SwitcherView>

    init() {
        panel = NonactivatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        hosting = NSHostingView(rootView: SwitcherView(model: model))
        panel.contentView = hosting
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.title = "AppSwitch — 窗口切换"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isMovableByWindowBackground = true
    }

    var containsMouse: Bool { panel.frame.contains(NSEvent.mouseLocation) }

    func show(acceptsKeyboardFocus: Bool = false, activateApplication: Bool = false) {
        panel.acceptsKeyboardFocus = acceptsKeyboardFocus
        resize(center: true)
        if acceptsKeyboardFocus {
            if activateApplication { NSApp.activate(ignoringOtherApps: true) }
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func resize(center: Bool = false) {
        let rowHeight: CGFloat = model.loading ? 160 : (model.rows.isEmpty ? 170 : CGFloat(min(model.rows.count, 6)) * 76 + 24)
        let height: CGFloat = 128 + rowHeight + (model.message != nil && !model.rows.isEmpty ? 28 : 0)
        var rect = NSRect(x: panel.frame.minX, y: panel.frame.midY - height / 2, width: 560, height: height)
        if center || panel.frame.isEmpty {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                rect.origin = NSPoint(x: frame.midX - rect.width / 2, y: frame.midY - rect.height / 2 + 40)
            }
        }
        panel.setFrame(rect, display: true)
    }

    func hide() { panel.orderOut(nil) }
}
