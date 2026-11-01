/// A global shortcut as the config writes it: "ctrl+alt+m". Keys are letters and digits, by ANSI position.
public struct Shortcut: Equatable, Sendable {
    public var ctrl = false, alt = false, cmd = false, shift = false
    public var key: String

    public static let keyCodes: [String: Int64] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
        "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    public init(ctrl: Bool = false, alt: Bool = false, cmd: Bool = false, shift: Bool = false, key: String) {
        self.ctrl = ctrl; self.alt = alt; self.cmd = cmd; self.shift = shift; self.key = key
    }

    /// nil for anything without a modifier other than shift, or with an unknown key or part.
    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.popLast(), Self.keyCodes[last] != nil else { return nil }
        key = last
        for p in parts {
            switch p {
            case "ctrl": ctrl = true
            case "alt", "opt", "option": alt = true
            case "cmd", "command": cmd = true
            case "shift": shift = true
            default: return nil
            }
        }
        guard ctrl || alt || cmd else { return nil }
    }

    public var text: String { ([ctrl ? "ctrl" : nil, alt ? "alt" : nil, shift ? "shift" : nil, cmd ? "cmd" : nil].compactMap { $0 } + [key]).joined(separator: "+") }
    public var symbol: String { (ctrl ? "⌃" : "") + (alt ? "⌥" : "") + (shift ? "⇧" : "") + (cmd ? "⌘" : "") + key.uppercased() }
    public var keyCode: Int64 { Self.keyCodes[key] ?? -1 }
    /// Plain Ctrl+key belongs to HyprMac on Greg's setup.
    public var clashesWithHyprMac: Bool { ctrl && !alt && !cmd }

    public static func key(forCode code: Int64) -> String? { keyCodes.first { $0.value == code }?.key }
}

/// What turns the keyboard mode on (`[keys] leader`): an F key, held or tapped; a chord, which only taps; or a lone
/// modifier (ctrl, alt, cmd), which turns the mode on by a clean tap and, held, only takes the banner's letters.
public enum Leader: Equatable, Sendable {
    case key(code: Int64, name: String)
    case chord(Shortcut)
    case modifier(String)

    public static let fKeys: [String: Int64] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]
    public static let modifiers: [String: String] = ["ctrl": "ctrl", "control": "ctrl", "alt": "alt", "opt": "alt", "option": "alt",
                                                     "cmd": "cmd", "command": "cmd"]

    public init?(_ text: String) {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let code = Self.fKeys[t] { self = .key(code: code, name: t) }
        else if let m = Self.modifiers[t] { self = .modifier(m) }
        else if let s = Shortcut(t) { self = .chord(s) }
        else { return nil }
    }

    /// As config.toml writes it.
    public var text: String {
        switch self {
        case .key(_, let name): name
        case .chord(let s): s.text
        case .modifier(let m): m
        }
    }

    public var symbol: String {
        switch self {
        case .key(_, let name): name.uppercased()
        case .chord(let s): s.symbol
        case .modifier("ctrl"): "⌃ Ctrl"
        case .modifier("alt"): "⌥ Option"
        case .modifier(let m): "⌘ \(m == "cmd" ? "Cmd" : m)"
        }
    }

    /// What `[notifications] hold` could be: an F key or a modifier, never a chord.
    var isOldHoldKey: Bool { if case .chord = self { false } else { true } }
}
