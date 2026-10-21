import AppKit
import Carbon

/// Carbon registers a shortcut, not a stream of keystrokes. No Accessibility permission is used.
final class HotKeyController {
    enum Shortcut: String, CaseIterable, Identifiable {
        case commandShiftSpace
        case commandOptionR
        var id: String { rawValue }
        var label: String { self == .commandShiftSpace ? "⌘ ⇧ Space" : "⌘ ⌥ R" }
        var keyCode: UInt32 { self == .commandShiftSpace ? UInt32(kVK_Space) : UInt32(kVK_ANSI_R) }
        var modifiers: UInt32 { self == .commandShiftSpace ? UInt32(cmdKey | shiftKey) : UInt32(cmdKey | optionKey) }
    }

    var onPress: (() -> Void)?
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var selected: Shortcut?

    private(set) var handlerStatus: OSStatus = OSStatus(eventNotHandledErr)
    private(set) var registrationStatus: OSStatus = OSStatus(eventNotHandledErr)
    var diagnostic: String { "handler=\(handlerStatus), registration=\(registrationStatus), key=\(selected?.keyCode ?? 0), modifiers=\(selected?.modifiers ?? 0)" }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == OSType(0x524C4159), identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<HotKeyController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { controller.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        precondition(Thread.isMainThread)
        installHandlerIfNeeded()
        guard handlerStatus == noErr, handler != nil else { return false }
        // Restore the previous shortcut if the new one is already reserved.
        let previous = selected
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        selected = nil
        if install(shortcut) { return true }
        if let previous { _ = install(previous) }
        return false
    }

    private func install(_ shortcut: Shortcut) -> Bool {
        let identifier = EventHotKeyID(signature: OSType(0x524C4159), id: 1) // RLAY
        registrationStatus = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &registration)
        guard registrationStatus == noErr else { registration = nil; return false }
        selected = shortcut
        return true
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }
}
