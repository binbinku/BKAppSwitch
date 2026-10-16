import AppKit

// Never replace a running ad-hoc app: its old process and the new binary have
// different identities, so granting permission to one does not grant the other.
let running = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == "dev.appswitch.app" && !$0.isTerminated
}
if !running.isEmpty {
    fputs("请先退出所有 AppSwitch 实例，再构建或安装。覆盖运行中的应用会造成授权版本不一致。\n", stderr)
    exit(1)
}
