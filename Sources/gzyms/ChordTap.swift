import AppKit
import ApplicationServices
import GzymsCore
import GzymsUI
import Synchronization

/// The keyboard: one session event tap that feeds `KeyNav` (the leader, the mode, the banner's letters) and catches
/// `[shortcuts] mic_mute`. Swallows only what those claim. Needs Accessibility.
///
/// The tap runs on its own thread and decides from `TapCore`'s state alone, so typing never waits for a busy main
/// thread. What it decides reaches the main thread afterwards.
@MainActor
final class ChordTap {
    var onMute: () -> Void = {}
    /// Enter or the open letter while the armageddon is up.
    var onArmageddon: () -> Void = {}
    /// The keyboard mode: its state after each key (nil = off) and what to do.
    var onNav: (NavSnapshot?, [NavAction]) -> Void = { _, _ in }
    /// What the hints point at when the mode starts: the focused bar's targets, kept fresh by the app.
    var navTargets: [HintTarget] { get { core.read(\.navTargets) } set { core.write { $0.navTargets = newValue } } }
    /// `[shortcuts] mic_mute`: works in every app, banner or not.
    var micShortcut: Shortcut? { get { core.read(\.micShortcut) } set { core.write { $0.micShortcut = newValue } } }
    /// Whether a banner is up: only then do its letters mean anything.
    var bannerUp: Bool {
        get { core.read(\.bannerUp) }
        set { if newValue != bannerUp { core.navEvent(.banner(up: newValue)) } }
    }
    /// Whether banners wait under it: only then does a held modifier leader take next and previous (⌃N/⌃P are
    /// history in a terminal).
    var queued: Bool { get { core.read(\.queued) } set { core.write { $0.queued = newValue } } }
    /// A shortcut recorder is listening: every key goes to it, the leader too.
    var paused: Bool { get { core.read(\.paused) } set { core.write { $0.paused = newValue } } }
    /// The armageddon is on screen.
    var armageddon: Bool { get { core.read(\.armageddon) } set { core.write { $0.armageddon = newValue } } }
    private let core = TapCore()
    private var started = false

    init() {
        core.deliver = { [weak self] out in
            DispatchQueue.main.async {
                guard let self else { return }
                switch out {
                case .mute: self.onMute()
                case .armageddon: self.onArmageddon()
                case .nav(let shown, let actions): self.onNav(shown, actions)
                }
            }
        }
    }

    /// What the banner's hint row shows right now; nil = none.
    var hints: ChordHints? { core.hints }

    /// The hints the leader would show, for the pointer over the banner.
    var hoverHints: ChordHints {
        core.peek { s in
            guard case .modifier(let m)? = s.leader else { return ChordHints(snoozeMinutes: nil, verbs: s.verbs) }
            return ChordHints(snoozeMinutes: nil, verbs: s.verbs, hold: String(Leader.modifier(m).symbol.prefix(1)))
        }
    }

    /// `[keys]`: a new leader, timeout, hint letters or verbs end a running mode.
    func configureNav(leader: Leader?, idleTimeout: Double, hintChars: String, verbs: Verbs) {
        core.navEvent(.off)
        core.write {
            var nav = KeyNav(hintChars: hintChars, idleTimeout: idleTimeout, verbs: verbs, modifierLeader: TapCore.isModifier(leader))
            _ = nav.handle(.banner(up: $0.bannerUp), now: 0)
            $0.leader = leader; $0.nav = nav; $0.verbs = verbs; $0.leaderHeld = false
        }
    }

    /// From outside the tap: `gzyms keys on|off`, an app switch, sleep, a screen change.
    func nav(on: Bool) { core.navEvent(on ? .on(navTargets) : .off) }

    /// A bar's popup opened or closed (nil); outside the mode that is the mouse, and its keys then take the mode on.
    func popup(_ id: String?) { core.navEvent(.popup(id, navTargets)) }

    /// Called again once Accessibility is granted, so no restart is needed.
    func start() {
        guard !started else { return }
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else { log("chords: needs Accessibility"); return }
        started = true
        let core = core
        let thread = Thread { core.run() }
        thread.name = "gzyms.keys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}

enum TapOutput: Sendable { case mute, armageddon, nav(NavSnapshot?, [NavAction]) }

/// The keyboard mode as the bar draws it.
struct NavSnapshot: Sendable {
    var hints: [String: String]
    var typed: String
}

/// Everything the tap decides from, behind one lock. Lives on the tap's thread; the main thread only writes settings in.
final class TapCore: Sendable {
    /// Unchecked for the run loop timers: they are touched only under the lock.
    struct State: @unchecked Sendable {
        var micShortcut: Shortcut?
        var bannerUp = false
        var queued = false
        var paused = false
        var armageddon = false
        var tap: CFMachPort?
        var leader: Leader?
        /// A modifier leader is down (from `flagsChanged`).
        var leaderHeld = false
        var verbs = Verbs()
        var nav = KeyNav()
        var navTargets: [HintTarget] = []
        /// Checks the idle timeout once a second, only while the mode is on. On the tap thread's run loop.
        var idleTimer: CFRunLoopTimer?
        /// Fires once, `KeyNav.snoozeSettle` after a z, so a pending snooze settles.
        var snoozeTimer: CFRunLoopTimer?
        var runLoop: CFRunLoop?
    }

    private let state = Mutex(State())
    /// Set once by `ChordTap.init`, before the thread starts.
    nonisolated(unsafe) var deliver: @Sendable (TapOutput) -> Void = { _ in }

    func read<T: Sendable>(_ key: KeyPath<State, T> & Sendable) -> T { state.withLock { $0[keyPath: key] } }
    func write(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
    func peek<T: Sendable>(_ get: (State) -> T) -> T { state.withLock { get($0) } }

    static func isModifier(_ l: Leader?) -> Bool { if case .modifier? = l { true } else { false } }

    static func mask(_ modifier: String) -> CGEventFlags {
        switch modifier {
        case "ctrl": .maskControl
        case "alt": .maskAlternate
        default: .maskCommand
        }
    }

    var hints: ChordHints? {
        state.withLock { s in
            guard s.bannerUp else { return nil }
            if s.nav.on && s.nav.popup == nil { return ChordHints(snoozeMinutes: s.nav.snoozePreview, verbs: s.verbs) }
            if case .modifier(let m)? = s.leader, s.leaderHeld {
                return ChordHints(snoozeMinutes: s.nav.snoozePreview, verbs: s.verbs, hold: String(Leader.modifier(m).symbol.prefix(1)))
            }
            return nil
        }
    }

    /// The tap thread's body: creates the tap here, so its callbacks come on this thread, and never returns.
    func run() {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: chordTapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log("chords: could not create the keyboard tap"); return
        }
        let rl = CFRunLoopGetCurrent()
        write { $0.tap = t; $0.runLoop = rl }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        log("chords: on")
        CFRunLoopRun()
    }

    /// true = swallow the event. Runs on the tap thread.
    fileprivate func handle(_ type: CGEventType, keyCode: Int64, flags: CGEventFlags, repeating: Bool) -> Bool {
        var out: [TapOutput] = []
        let swallow = state.withLock { s in Self.handle(&s, type, keyCode: keyCode, flags: flags, repeating: repeating, out: &out, core: self) }
        out.forEach(deliver)
        return swallow
    }

    /// An event for the mode from outside the tap (any thread).
    func navEvent(_ e: NavEvent) {
        var out: [TapOutput] = []
        state.withLock { s in _ = Self.nav(&s, e, out: &out, core: self) }
        out.forEach(deliver)
    }

    private static func handle(_ s: inout State, _ type: CGEventType, keyCode: Int64, flags: CGEventFlags, repeating: Bool,
                               out: inout [TapOutput], core: TapCore) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = s.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("chords: tap re-enabled")
            // Keys went past the tap meanwhile: a mode left on would no longer match what the apps saw.
            s.leaderHeld = false
            _ = nav(&s, .off, out: &out, core: core)
            return false
        }
        if s.paused { return false }
        if type == .keyDown, let m = s.micShortcut, matches(m, keyCode: keyCode, flags: flags) {
            out.append(.mute)
            return true
        }
        // The armageddon takes Enter and its open letter, no leader; the rest goes on (it is never dismissed by key).
        if s.armageddon, type == .keyDown {
            var a = KeyNav(context: .armageddon, verbs: s.verbs)
            if a.handle(.key(navKey(keyCode, flags: flags)), now: 0).swallow { out.append(.armageddon); return true }
        }
        return navKey(&s, type, keyCode: keyCode, flags: flags, repeating: repeating, out: &out, core: core)
    }

    private static func matches(_ sc: Shortcut, keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == sc.keyCode && flags.contains(.maskControl) == sc.ctrl && flags.contains(.maskAlternate) == sc.alt
            && flags.contains(.maskCommand) == sc.cmd && flags.contains(.maskShift) == sc.shift
    }

    // MARK: - The keyboard mode (KeyNav)

    /// The leader, and every key while the mode is on or a modifier leader is held.
    private static func navKey(_ s: inout State, _ type: CGEventType, keyCode: Int64, flags: CGEventFlags, repeating: Bool,
                               out: inout [TapOutput], core: TapCore) -> Bool {
        var flags = flags
        switch s.leader {
        case .key(let code, _)? where keyCode == code && type != .flagsChanged:
            return nav(&s, type == .keyDown ? .leaderDown(s.navTargets) : .leaderUp, out: &out, core: core)
        case .chord(let sc)? where matches(sc, keyCode: keyCode, flags: flags):
            // A chord only taps: down and up at once. Held, its auto-repeat must not flip the mode on and off.
            if type == .keyDown && !repeating {
                _ = nav(&s, .leaderDown(s.navTargets), out: &out, core: core)
                _ = nav(&s, .leaderUp, out: &out, core: core)
            }
            return true
        case .modifier(let m)?:
            let mine = mask(m)
            if type == .flagsChanged {
                let down = flags.contains(mine)
                let others = !flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]).subtracting(mine).isEmpty
                if down && !s.leaderHeld {
                    s.leaderHeld = true
                    _ = nav(&s, .leaderDown(s.navTargets), out: &out, core: core, redraw: s.bannerUp)
                    if others { _ = nav(&s, .key(.modified), out: &out, core: core) }
                } else if !down && s.leaderHeld {
                    s.leaderHeld = false
                    _ = nav(&s, .leaderUp, out: &out, core: core, redraw: s.bannerUp)
                } else if down && others {
                    _ = nav(&s, .key(.modified), out: &out, core: core)  // another modifier joined: not a clean tap
                }
                return false  // the apps must always see modifiers change
            }
            if s.leaderHeld { flags.remove(mine) }
        default: break
        }
        guard type == .keyDown, s.nav.on || s.leaderHeld || s.nav.mouse != nil else { return false }
        var k = navKey(keyCode, flags: flags)
        // Held without the mode, the modifier takes the stack's letters only while banners wait.
        if s.leaderHeld, !s.nav.on, !s.queued, case .letter(let c) = k, ["j", "k", s.verbs.next, s.verbs.prev].contains(c) { k = .modified }
        return nav(&s, .key(k), out: &out, core: core)
    }

    private static func navKey(_ keyCode: Int64, flags: CGEventFlags) -> NavKey {
        NavKey(keyCode: keyCode, modified: !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty)
    }

    /// Feeds the engine; reports to the bar when anything changed (or `redraw` asks); runs the idle check while the
    /// mode is on and the snooze clock while a z waits.
    private static func nav(_ s: inout State, _ e: NavEvent, out: inout [TapOutput], core: TapCore, redraw: Bool = false) -> Bool {
        if case .banner(let up) = e { s.bannerUp = up }
        let before = (s.nav.on, s.nav.typed, s.nav.popup, s.nav.snoozePreview)
        let r = s.nav.handle(e, now: ProcessInfo.processInfo.systemUptime)
        if redraw || !r.actions.isEmpty || before != (s.nav.on, s.nav.typed, s.nav.popup, s.nav.snoozePreview) {
            // In a popup the hints do nothing, so they go; the gold edge stays and Esc brings them back (Greg).
            out.append(.nav(s.nav.on ? NavSnapshot(hints: s.nav.popup == nil ? s.nav.hints : [:], typed: s.nav.typed) : nil, r.actions))
        }
        if s.nav.on, s.idleTimer == nil, let rl = s.runLoop {
            let t = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { _ in core.idleCheck() }
            CFRunLoopAddTimer(rl, t, .commonModes)
            s.idleTimer = t
        } else if !s.nav.on, let t = s.idleTimer {
            CFRunLoopTimerInvalidate(t)  // safe from any thread
            s.idleTimer = nil
        }
        if let t = s.snoozeTimer { CFRunLoopTimerInvalidate(t); s.snoozeTimer = nil }
        if s.nav.snoozePreview != nil, let rl = s.runLoop {
            let t = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + KeyNav.snoozeSettle, 0, 0, 0) { _ in core.navEvent(.tick) }
            CFRunLoopAddTimer(rl, t, .commonModes)
            s.snoozeTimer = t
        }
        return r.swallow
    }

    private func idleCheck() {
        let now = ProcessInfo.processInfo.systemUptime
        if read(\.nav).expired(now: now) { log("keys: idle, mode off"); navEvent(.off) }
    }
}

/// A C callback cannot capture; the core rides in `refcon`. Runs on the tap thread.
private func chordTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let core = Unmanaged<TapCore>.fromOpaque(refcon).takeUnretainedValue()
    let swallow = core.handle(type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                              repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    return swallow ? nil : Unmanaged.passUnretained(event)
}
