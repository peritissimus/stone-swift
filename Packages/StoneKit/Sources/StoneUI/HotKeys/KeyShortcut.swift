import Carbon.HIToolbox

/// A global chord parsed from Stone's Electron accelerator text, e.g. `Alt+Space` or
/// `CommandOrControl+Shift+N`. Any token it does not know rejects the whole chord, so a
/// misread can never register something broader than the user asked for.
struct KeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    private static let modifierTokens: [String: (flag: Int, symbol: String)] = [
        "ctrl": (controlKey, "⌃"), "control": (controlKey, "⌃"),
        "alt": (optionKey, "⌥"), "option": (optionKey, "⌥"),
        "shift": (shiftKey, "⇧"),
        "cmd": (cmdKey, "⌘"), "command": (cmdKey, "⌘"), "super": (cmdKey, "⌘"), "meta": (cmdKey, "⌘"),
        "commandorcontrol": (cmdKey, "⌘"), "cmdorctrl": (cmdKey, "⌘"),
    ]

    private struct Key {
        let code: Int
        let label: String
        var isFunctionKey = false
    }

    /// Every main key Stone desktop's recorder (`accelerator.ts` `codeToKey`) can write.
    private static let keyTokens: [String: Key] = {
        var keys: [String: Key] = [
            "space": Key(code: kVK_Space, label: "Space"), "return": Key(code: kVK_Return, label: "↩"),
            "enter": Key(code: kVK_Return, label: "↩"), "tab": Key(code: kVK_Tab, label: "⇥"),
            "esc": Key(code: kVK_Escape, label: "⎋"), "escape": Key(code: kVK_Escape, label: "⎋"),
            "backspace": Key(code: kVK_Delete, label: "⌫"), "delete": Key(code: kVK_ForwardDelete, label: "⌦"),
            "up": Key(code: kVK_UpArrow, label: "↑"), "down": Key(code: kVK_DownArrow, label: "↓"),
            "left": Key(code: kVK_LeftArrow, label: "←"), "right": Key(code: kVK_RightArrow, label: "→"),
            "-": Key(code: kVK_ANSI_Minus, label: "-"), "=": Key(code: kVK_ANSI_Equal, label: "="),
            "[": Key(code: kVK_ANSI_LeftBracket, label: "["), "]": Key(code: kVK_ANSI_RightBracket, label: "]"),
            "\\": Key(code: kVK_ANSI_Backslash, label: "\\"), ";": Key(code: kVK_ANSI_Semicolon, label: ";"),
            "'": Key(code: kVK_ANSI_Quote, label: "'"), ",": Key(code: kVK_ANSI_Comma, label: ","),
            ".": Key(code: kVK_ANSI_Period, label: "."), "/": Key(code: kVK_ANSI_Slash, label: "/"),
            "`": Key(code: kVK_ANSI_Grave, label: "`"),
        ]
        let letters: [Int] = [
            kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
            kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
            kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
            kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        ]
        for (offset, code) in letters.enumerated() {
            let letter = String(UnicodeScalar(UInt8(97 + offset)))
            keys[letter] = Key(code: code, label: letter.uppercased())
        }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                      kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (digit, code) in digits.enumerated() { keys["\(digit)"] = Key(code: code, label: "\(digit)") }
        // Carbon names F1–F20; Stone can record F21–F24, which macOS keyboards cannot send.
        let functions = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functions.enumerated() {
            keys["f\(index + 1)"] = Key(code: code, label: "F\(index + 1)", isFunctionKey: true)
        }
        return keys
    }()

    /// Nil for anything malformed: an unknown token, no key, two keys, or no modifier
    /// (a bare key would swallow ordinary typing in every app). F-keys may stand alone.
    init?(parsing text: String) {
        var flags: UInt32 = 0
        var symbols = ""
        var key: Key?
        let tokens = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        for token in tokens {
            if let modifier = Self.modifierTokens[token] {
                if flags & UInt32(modifier.flag) == 0 { symbols += modifier.symbol }
                flags |= UInt32(modifier.flag)
            } else if let named = Self.keyTokens[token], key == nil {
                key = named
            } else {
                return nil
            }
        }
        guard let key, flags != 0 || key.isFunctionKey else { return nil }
        keyCode = UInt32(key.code)
        modifiers = flags
        display = symbols + key.label
    }
}
