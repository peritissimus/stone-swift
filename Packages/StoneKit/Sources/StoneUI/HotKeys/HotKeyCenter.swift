import Carbon.HIToolbox

/// Carbon's hot-key API is still the only public way to claim a system-wide chord.
@MainActor
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5354_4E45  // "STNE"

    /// Returns false when another app already owns the chord.
    @discardableResult
    func register(_ shortcut: KeyShortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = action
        return true
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) -> OSStatus {
        guard let handler = handlers[id] else { return OSStatus(eventNotHandledErr) }
        handler()
        return noErr
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyEventHandler, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}

private func hotKeyEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers hot keys on the main run loop.
    return MainActor.assumeIsolated { center.fire(id.id) }
}
