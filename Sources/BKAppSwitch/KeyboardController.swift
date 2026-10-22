import AppKit
import Carbon

enum SwitchKeyAction { case begin(Int), move(Int), commit, cancel }

/// Global activation uses registered hotkeys; navigation uses our own key panel.
/// Neither operation needs a global keyboard event tap or Input Monitoring.
final class KeyboardController {
    var onAction: ((SwitchKeyAction) -> Void)?
    var isSwitching: (() -> Bool)?
    var onHotKey: (() -> Void)?
    var shortcut: Shortcut = .optionTab {
        didSet { if oldValue != shortcut, isRunning { _ = start() } }
    }
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var localMonitor: Any?
    private var releaseTimer: Timer?
    private var trackingOptionRelease = false
    private var swallowed: Set<UInt16> = []
    private(set) var lastError: OSStatus = noErr
    var isRunning: Bool { handler != nil && hotKeys.count == 2 }

    @discardableResult func start() -> Bool {
        stop()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x43535748 else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<KeyboardController>.fromOpaque(context).takeUnretainedValue()
            controller.hotKeyPressed(direction: id.id == 2 ? -1 : 1)
            return noErr
        }
        lastError = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                                       Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard lastError == noErr else { stop(); return false }
        let modifiers = UInt32(optionKey) | (shortcut == .controlOptionTab ? UInt32(controlKey) : 0)
        for reverse in [false, true] {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x43535748, id: reverse ? 2 : 1)
            lastError = RegisterEventHotKey(UInt32(shortcut.keyCode), modifiers | (reverse ? UInt32(shiftKey) : 0),
                                           id, GetApplicationEventTarget(), 0, &reference)
            guard lastError == noErr, let reference else { stop(); return false }
            hotKeys.append(reference)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocal(event)
        }
        return true
    }

    private func hotKeyPressed(direction: Int) {
        onHotKey?()
        trackingOptionRelease = true
        onAction?(isSwitching?() == true ? .move(direction) : .begin(direction))
        guard isSwitching?() == true else { trackingOptionRelease = false; return }
        releaseTimer?.invalidate()
        // Poll only the public modifier state, only while the switcher is open.
        // This also catches a very fast release during window enumeration.
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isSwitching?() == true else { self.usePersistentSelection(); return }
            if self.trackingOptionRelease && !NSEvent.modifierFlags.contains(.option) {
                self.usePersistentSelection()
                self.onAction?(.commit)
            }
        }
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp { return swallowed.remove(event.keyCode) == nil ? event : nil }
        guard isSwitching?() == true else { return event }
        if event.type == .flagsChanged {
            if trackingOptionRelease && !event.modifierFlags.contains(.option) {
                usePersistentSelection()
                onAction?(.commit)
            }
            return event
        }
        if event.modifierFlags.contains(.command) && event.keyCode == 48 {
            onAction?(.cancel)
            return event
        }
        swallowed.insert(event.keyCode)
        switch event.keyCode {
        case 53: onAction?(.cancel)
        case 36, 76: onAction?(.commit)
        case 125, 124: onAction?(.move(1))
        case 126, 123: onAction?(.move(-1))
        case 48: onAction?(.move(event.modifierFlags.contains(.shift) ? -1 : 1))
        default: break
        }
        return nil
    }

    func usePersistentSelection() {
        trackingOptionRelease = false
        releaseTimer?.invalidate()
        releaseTimer = nil
    }

    func stop() {
        usePersistentSelection()
        for key in hotKeys { UnregisterEventHotKey(key) }
        hotKeys = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        swallowed.removeAll()
    }

    deinit { stop() }
}
