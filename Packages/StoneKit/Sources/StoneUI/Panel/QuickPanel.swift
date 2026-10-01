import AppKit
import Carbon.HIToolbox

/// The one Stone window: a borderless floating panel that never activates the app, so hiding
/// it hands the keyboard straight back to whatever you were typing in.
/// It turns keys into intents before the text views see them; `onKey` returning false passes one on.
final class QuickPanel: NSPanel {
    enum KeyIntent: Equatable {
        case submit
        case newline
        case escape
        case close
        case move(Int)
        case toggleBrowse
        case today
    }

    var onKey: ((KeyIntent) -> Bool)?

    /// A non-activating panel has no menu bar to route edit chords, so it answers them itself.
    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "a": #selector(NSResponder.selectAll(_:)), "z": Selector(("undo:")),
    ]

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.Size.capture),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let intent = intent(for: event), onKey?(intent) == true { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == [.command, .shift], key == "z" {
            return NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
        }
        guard modifiers == .command, let action = Self.editActions[key] else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    private func intent(for event: NSEvent) -> KeyIntent? {
        // While an input method is composing, every key is its to pick candidates and commit.
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if modifiers.isEmpty { return .submit }
            return modifiers == .shift ? .newline : nil
        case kVK_Escape where modifiers.isEmpty: return .escape
        case kVK_UpArrow where modifiers.isEmpty: return .move(-1)
        case kVK_DownArrow where modifiers.isEmpty: return .move(1)
        default: break
        }
        // By character, so the chords follow the letters on Dvorak, Colemak or AZERTY keys.
        // `charactersIgnoringModifiers` keeps only Shift, so ⌥O still reads "o", not "ø".
        switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
        case (.option, "o"): return .toggleBrowse
        case (.command, "j"): return .today
        case (.command, "w"): return .close
        case (.control, "n"): return .move(1)
        case (.control, "p"): return .move(-1)
        default: return nil
        }
    }
}
