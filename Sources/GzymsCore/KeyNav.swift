/// A key as the keyboard mode sees it. `.modified` = anything with ⌘, ⌃ or ⌥: it belongs to the apps.
public enum NavKey: Equatable, Sendable {
    case letter(String), esc, enter, up, down, left, right, modified, other

    /// From a macOS key code; `modified` = ⌘, ⌃ or ⌥ held.
    public init(keyCode: Int64, modified: Bool) {
        if modified { self = .modified; return }
        switch keyCode {
        case 36, 76: self = .enter
        case 53: self = .esc
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: self = Shortcut.key(forCode: keyCode).map(NavKey.letter) ?? .other
        }
    }
}

/// Something on the bar a hint can point at: a pill with a popup, or an action (a workspace, a plugin click).
public struct HintTarget: Equatable, Sendable {
    public var id: String
    public var popup: Bool
    public init(id: String, popup: Bool) { self.id = id; self.popup = popup }
}

/// What the banner does from the keyboard.
public enum ChordAction: Equatable, Sendable { case open, dismiss, alt, snooze(minutes: Int), next, previous }

/// The banner's letters (`[keys.verbs]`, formerly `[notifications.letters]`). In an open popup `open` also chooses
/// a row and `dismiss` removes one. j and k always step through the waiting banners too.
public struct Verbs: Equatable, Sendable {
    public var open = "o", dismiss = "x", alt = "a", snooze = "z", next = "n", prev = "p"
    public init(open: String = "o", dismiss: String = "x", alt: String = "a", snooze: String = "z", next: String = "n", prev: String = "p") {
        self.open = open; self.dismiss = dismiss; self.alt = alt; self.snooze = snooze; self.next = next; self.prev = prev
    }

    /// Every letter by its config key.
    public var all: [(key: String, letter: String)] {
        [("open", open), ("dismiss", dismiss), ("snooze", snooze), ("alt", alt), ("next", next), ("prev", prev)]
    }
}

public enum NavEvent: Equatable, Sendable {
    /// The targets on the bar the mode starts on, left to right; frozen until the mode ends.
    case leaderDown([HintTarget])
    case leaderUp
    case key(NavKey)
    /// From outside (`gzyms keys on|off`, an app switch, sleep, a screen change).
    case on([HintTarget]), off
    /// A banner came up or went: only then do the banner's letters mean anything.
    case banner(up: Bool)
    /// The clock, for a snooze waiting to settle.
    case tick
}

/// Who the keys are for: the bar (the leader's mode), or a window that takes a few of them while it is up,
/// no leader needed (the meeting preview or Settings while in front, the armageddon over everything).
public enum NavContext: Sendable { case bar, preview, armageddon, settings }

public enum NavAction: Equatable, Sendable {
    case open(String), activate(String)
    /// In an open popup: the highlighted row moves, is chosen, is removed, takes its second action;
    /// `side` goes to the neighbouring pill's popup.
    case move(Int), choose, remove, alt, side(Int)
    /// The popup closes, the hints stay.
    case back
    case banner(ChordAction)
    /// The meeting preview's keys: c camera, m mic, s speakers, t test sound.
    case preview(String)
    case exit
}

/// The keyboard mode (spec 2026-11-01): the leader turns it on, hints name what is on the bar, a popup takes
/// j/k/h/l, Enter or o, x and Esc, a banner takes its verbs. Tapped, the leader leaves the mode on; held with a key,
/// letting go ends it, unless that key opened a popup. Esc steps back one level, the leader again or the idle
/// timeout end it.
///
/// A lone modifier as the leader (`modifierLeader`) must leave the apps' shortcuts alone: only a clean tap turns
/// the mode on or off, and held it takes nothing but the banner's verbs while a banner is up (the old Ctrl chords).
/// Pure: the tap feeds it events and acts on what comes back.
public struct KeyNav: Sendable {
    /// Letters that are never verbs (h j k l o x a z f, and n p of the banner stack).
    public static let defaultHintChars = "bcdegimqrstuvwy"
    /// Keys with a job in the mode whatever the verbs say.
    public static let fixedVerbs = "hjklf"
    /// The default verbs and the fixed ones; never a hint.
    public static let verbs = fixedVerbs + Verbs().all.map(\.letter).joined()
    /// z, zz, zzz, zzzz; more z stays at the max.
    public static let snoozeMinutes = [3, 5, 10, 30]
    /// How long after the last z the snooze settles, when no held leader settles it.
    public static let snoozeSettle = 0.7

    public private(set) var on = false
    /// Target id → its hint.
    public private(set) var hints: [String: String] = [:]
    /// Letters of a two-letter hint typed so far.
    public private(set) var typed = ""
    /// The open popup's target id; nil = the bar's level.
    public private(set) var popup: String?
    private var targets: [HintTarget] = []
    private var pending: [HintTarget] = []
    private var held = false
    private var usedWhileHeld = false
    private var lastAt = 0.0
    private var bannerUp = false
    private var zs = 0, zAt = 0.0
    private let chars: String
    private let idleTimeout: Double
    private let verbs: Verbs
    private let modifierLeader: Bool
    private let context: NavContext
    /// The meeting preview's own letters.
    public static let previewKeys = "cmst"

    public init(context: NavContext = .bar, hintChars: String = defaultHintChars, idleTimeout: Double = 30, verbs: Verbs = Verbs(), modifierLeader: Bool = false) {
        let kept = Self.hintChars(hintChars, verbs: verbs)
        chars = kept.count >= 2 ? kept : Self.hintChars(Self.defaultHintChars, verbs: verbs)
        self.idleTimeout = idleTimeout
        self.verbs = verbs
        self.modifierLeader = modifierLeader
        self.context = context
    }

    /// The hint letters left once the verbs are taken out.
    public static func hintChars(_ chars: String, verbs: Verbs) -> String {
        let taken = fixedVerbs + verbs.all.map(\.letter).joined()
        return String(chars.filter { !taken.contains($0) })
    }

    /// Minutes the pending z's would snooze for; nil = no z pressed.
    public var snoozePreview: Int? { zs == 0 ? nil : Self.snoozeMinutes[min(zs, Self.snoozeMinutes.count) - 1] }

    public mutating func handle(_ e: NavEvent, now: Double) -> (swallow: Bool, actions: [NavAction]) {
        if context != .bar {
            guard case .key(let k) = e else { return (false, []) }
            return window(k)
        }
        switch e {
        case .on(let t):
            // Only the first one starts the clock: anyone in the session can send `on`, and a repeated one
            // must not keep the mode (and the swallowed keys) alive past the idle timeout.
            if !on { enter(t); lastAt = now }
            return (false, [])
        case .off:
            zs = 0
            return (false, on ? exit() : [])
        case .banner(let up):
            bannerUp = up
            if !up { zs = 0 }  // a snooze is for the banner it was typed on
            return (false, [])
        case .tick:
            guard zs > 0, !held, now - zAt >= Self.snoozeSettle - 1e-9 else { return (false, []) }
            return (false, settle() + (on ? exit() : []))
        case .leaderDown(let t):
            guard !held else { return (!modifierLeader, []) }  // auto-repeat
            held = true; usedWhileHeld = false; lastAt = now
            if modifierLeader { pending = t; return (false, []) }  // decided when it goes up
            if on { return (true, exit()) }
            enter(t)
            return (true, [])
        case .leaderUp:
            held = false; lastAt = now
            let snooze = settle()
            if modifierLeader {
                guard !usedWhileHeld else { return (false, snooze) }
                if on { return (false, exit()) }
                enter(pending)
                return (false, [])
            }
            return (true, snooze + (on && usedWhileHeld && popup == nil ? exit() : []))
        case .key(let k):
            if held { usedWhileHeld = true }
            if modifierLeader, held, !on {
                // Held alone, the modifier is someone else's shortcut, except for the banner's verbs.
                guard bannerUp, case .letter(let c) = k, let a = banner(c, now: now) else { return (false, []) }
                return (true, a.actions)
            }
            // Modified keys go to the apps and, not being for us, do not keep the mode alive.
            guard on, k != .modified else { return (false, []) }
            lastAt = now
            return (true, popup == nil ? bar(k, now: now) : inPopup(k))
        }
    }

    /// The mode has seen no key of its own for `idleTimeout` seconds (0 = never).
    public func expired(now: Double) -> Bool { on && idleTimeout > 0 && now - lastAt >= idleTimeout }

    private mutating func bar(_ k: NavKey, now: Double) -> [NavAction] {
        switch k {
        case .esc:
            if zs > 0 { zs = 0; return [] }
            if !typed.isEmpty { typed = ""; return [] }
            return exit()
        case .letter(let c) where bannerUp && isBannerVerb(c):
            let a = banner(c, now: now)!
            return a.actions + (a.ends ? exit() : [])
        case .letter(let c) where chars.contains(c):
            typed += c
            if let id = hints.first(where: { $0.value == typed })?.key {
                typed = ""
                guard targets.first(where: { $0.id == id })?.popup == true else { return [.activate(id)] + exit() }
                popup = id
                return [.open(id)]
            }
            if !hints.values.contains(where: { $0.hasPrefix(typed) }) { typed = "" }
            return []
        default:
            typed = ""
            return []
        }
    }

    private func isBannerVerb(_ c: String) -> Bool { c == "j" || c == "k" || verbs.all.contains { $0.letter == c } }

    /// A banner verb: what it does, and whether it ends the mode. A z only counts; it settles later.
    /// Any other verb drops a pending snooze.
    private mutating func banner(_ c: String, now: Double) -> (actions: [NavAction], ends: Bool)? {
        guard isBannerVerb(c) else { return nil }
        if c == verbs.snooze { zs += 1; zAt = now; return ([], false) }
        zs = 0
        switch c {
        case verbs.open: return ([.banner(.open)], true)
        case verbs.dismiss: return ([.banner(.dismiss)], true)
        case verbs.alt: return ([.banner(.alt)], true)
        case verbs.next, "j": return ([.banner(.next)], false)
        default: return ([.banner(.previous)], false)
        }
    }

    private mutating func settle() -> [NavAction] {
        guard let m = snoozePreview else { return [] }
        zs = 0
        return [.banner(.snooze(minutes: m))]
    }

    /// A window's keys: Enter or open choose (join, open the armageddon, flip a setting), the rest go on as usual.
    private func window(_ k: NavKey) -> (swallow: Bool, actions: [NavAction]) {
        switch (context, k) {
        case (_, .enter), (_, .letter(verbs.open)): return (true, [.choose])
        case (.preview, .esc), (.settings, .esc): return (true, [.exit])
        case (.settings, .letter("h")), (.settings, .left): return (true, [.side(-1)])
        case (.settings, .letter("l")), (.settings, .right): return (true, [.side(1)])
        case (.settings, .letter("j")), (.settings, .down): return (true, [.move(1)])
        case (.settings, .letter("k")), (.settings, .up): return (true, [.move(-1)])
        case (.preview, .letter(let c)) where Self.previewKeys.contains(c): return (true, [.preview(c)])
        default: return (false, [])
        }
    }

    private mutating func inPopup(_ k: NavKey) -> [NavAction] {
        switch k {
        case .letter("j"), .down: return [.move(1)]
        case .letter("k"), .up: return [.move(-1)]
        case .letter("h"), .left: return [.side(-1)]
        case .letter("l"), .right: return [.side(1)]
        case .letter(verbs.dismiss): return [.remove]
        case .letter(verbs.alt): return [.alt]  // the app ends the mode once a second action ran
        case .letter(verbs.open), .enter: return [.choose] + exit()
        case .esc: popup = nil; return [.back]
        default: return []
        }
    }

    private mutating func enter(_ t: [HintTarget]) {
        on = true; targets = t; typed = ""; popup = nil
        hints = Dictionary(uniqueKeysWithValues: zip(t.map(\.id), Self.labels(count: t.count, chars: chars)))
    }

    private mutating func exit() -> [NavAction] {
        on = false; hints = [:]; typed = ""; popup = nil; targets = []; usedWhileHeld = false; zs = 0
        return [.exit]
    }

    /// `count` hints, none a prefix of another (Vimium): single letters while they last, then the first letters
    /// give way to two-letter hints. Shorter hints come first, so the left of the bar gets them.
    public static func labels(count: Int, chars: String) -> [String] {
        let letters = chars.map(String.init)
        guard count > 0, letters.count >= 2 else { return [] }
        var queue = [""], offset = 0
        while queue.count - offset < count || queue.count == 1 {
            let h = queue[offset]
            offset += 1
            queue += letters.map { h + $0 }
        }
        return Array(queue[offset..<offset + count])
    }
}
