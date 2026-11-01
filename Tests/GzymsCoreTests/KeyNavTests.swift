import Testing
@testable import GzymsCore

private let three = [HintTarget(id: "ws:1", popup: false), HintTarget(id: "widget:audio", popup: true), HintTarget(id: "bell", popup: true)]

/// Plays events at one second apart, returns every action in order.
@discardableResult
private func play(_ n: inout KeyNav, _ events: [NavEvent], from t: Double = 0) -> [NavAction] {
    events.enumerated().flatMap { i, e in n.handle(e, now: t + Double(i)).actions }
}

private func on(_ targets: [HintTarget] = three) -> KeyNav {
    var n = KeyNav()
    play(&n, [.leaderDown(targets), .leaderUp])
    return n
}

@Test func tapTurnsModeOnAndKeepsIt() {
    let n = on()
    #expect(n.on)
    #expect(n.hints == ["ws:1": "b", "widget:audio": "c", "bell": "d"])
    #expect(n.popup == nil)
}

@Test func leaderAgainEscAndOffTurnItOff() {
    for last in [[NavEvent.leaderDown(three), .leaderUp], [.key(.esc)], [.off]] {
        var n = on()
        let actions = play(&n, last)
        #expect(!n.on && n.hints.isEmpty)
        #expect(actions == [.exit])
    }
}

@Test func leaderKeysAreSwallowed() {
    var n = KeyNav()
    #expect(n.handle(.leaderDown(three), now: 0).swallow)
    #expect(n.handle(.leaderUp, now: 0).swallow)
}

@Test func autoRepeatedLeaderDownDoesNotToggle() {
    var n = KeyNav()
    play(&n, [.leaderDown(three), .leaderDown(three), .leaderDown(three), .leaderUp])
    #expect(n.on)
}

@Test func hintOnPopupTargetOpensIt() {
    var n = on()
    let r = n.handle(.key(.letter("c")), now: 5)
    #expect(r.swallow && r.actions == [.open("widget:audio")])
    #expect(n.on && n.popup == "widget:audio")
}

@Test func hintOnActionTargetActivatesAndExits() {
    var n = on()
    #expect(n.handle(.key(.letter("b")), now: 5).actions == [.activate("ws:1"), .exit])
    #expect(!n.on)
}

@Test func popupVerbs() {
    let cases: [(NavKey, [NavAction])] = [
        (.letter("j"), [.move(1)]), (.down, [.move(1)]), (.letter("k"), [.move(-1)]), (.up, [.move(-1)]),
        (.letter("h"), [.side(-1)]), (.left, [.side(-1)]), (.letter("l"), [.side(1)]), (.right, [.side(1)]),
        (.letter("x"), [.remove]), (.letter("a"), [.alt]),
    ]
    for (key, want) in cases {
        var n = on()
        play(&n, [.key(.letter("c"))])
        let r = n.handle(.key(key), now: 9)
        #expect(r.swallow && r.actions == want, "\(key)")
        #expect(n.on && n.popup == "widget:audio", "\(key) keeps the popup")
    }
    for key in [NavKey.enter, .letter("o")] {
        var n = on()
        play(&n, [.key(.letter("c"))])
        #expect(n.handle(.key(key), now: 9).actions == [.choose, .exit])
        #expect(!n.on)
    }
}

@Test func escStepsBack() {
    var n = on()
    play(&n, [.key(.letter("c"))])
    #expect(n.handle(.key(.esc), now: 9).actions == [.back])
    #expect(n.on && n.popup == nil && n.hints.count == 3)
    #expect(n.handle(.key(.esc), now: 10).actions == [.exit])
    #expect(!n.on)
}

@Test func heldLeaderChordEndsAtBarLevel() {
    var n = KeyNav()
    play(&n, [.leaderDown(three), .key(.letter("q"))])
    #expect(n.handle(.leaderUp, now: 5).actions == [.exit])
    #expect(!n.on)
}

@Test func heldLeaderOpeningPopupStays() {
    var n = KeyNav()
    play(&n, [.leaderDown(three), .key(.letter("c")), .leaderUp])
    #expect(n.on && n.popup == "widget:audio")
}

@Test func twoLetterHints() {
    let labels = KeyNav.labels(count: 20, chars: KeyNav.defaultHintChars)
    #expect(labels.count == 20 && Set(labels).count == 20)
    for a in labels { for b in labels where a != b { #expect(!b.hasPrefix(a), "\(a) is a prefix of \(b)") } }

    let targets = (0..<20).map { HintTarget(id: "t\($0)", popup: false) }
    var n = on(targets)
    let id = n.hints.first { $0.value.count == 2 }!.key, label = n.hints[id]!
    let first = n.handle(.key(.letter(String(label.first!))), now: 5)
    #expect(first.swallow && first.actions.isEmpty && n.typed == String(label.first!))
    #expect(n.handle(.key(.letter(String(label.last!))), now: 6).actions == [.activate(id), .exit])
}

@Test func unknownLetterIsSwallowedAndClearsTyped() {
    var n = on((0..<20).map { HintTarget(id: "t\($0)", popup: false) })
    let two = n.hints.values.first { $0.count == 2 }!
    play(&n, [.key(.letter(String(two.first!)))], from: 5)
    let r = n.handle(.key(.letter("1")), now: 6)
    #expect(r.swallow && r.actions.isEmpty && n.typed.isEmpty && n.on)
}

@Test func labelsNeverUseVerbs() {
    for count in [1, 15, 16, 60, 300] {
        for l in KeyNav.labels(count: count, chars: KeyNav.defaultHintChars) {
            #expect(l.allSatisfy { !"hjklxazfonp".contains($0) })
        }
    }
}

@Test func modifiedKeysPassAndDoNotResetTheIdleClock() {
    var n = on()  // last event at t = 1
    let r = n.handle(.key(.modified), now: 20)
    #expect(!r.swallow && r.actions.isEmpty && n.on)
    #expect(n.expired(now: 31))
}

@Test func offModePassesEverything() {
    var n = KeyNav()
    for k in [NavKey.letter("j"), .esc, .enter, .other] { #expect(!n.handle(.key(k), now: 0).swallow) }
}

@Test func otherKeysAreSwallowedInMode() {
    var n = on()
    let r = n.handle(.key(.other), now: 5)
    #expect(r.swallow && r.actions.isEmpty && n.on)
}

@Test func idleTimeout() {
    var n = on()  // last event at t = 1
    #expect(!n.expired(now: 30.9))
    #expect(n.expired(now: 31))
    play(&n, [.key(.letter("q"))], from: 20)
    #expect(!n.expired(now: 49))

    var never = KeyNav(idleTimeout: 0)
    play(&never, [.leaderDown(three), .leaderUp])
    #expect(!never.expired(now: 10_000))
    #expect(!KeyNav().expired(now: 10_000))  // off is never expired
}

// MARK: - The banner (stage 3)

/// The mode on (leader tapped) with a banner up.
private func onWithBanner(_ verbs: Verbs = Verbs()) -> KeyNav {
    var n = KeyNav(verbs: verbs)
    play(&n, [.banner(up: true), .leaderDown(three), .leaderUp])
    return n
}

@Test func bannerVerbsAtBarLevel() {
    for (letter, action) in [("o", ChordAction.open), ("x", .dismiss), ("a", .alt)] {
        var n = onWithBanner()
        let r = n.handle(.key(.letter(letter)), now: 5)
        #expect(r.swallow && r.actions == [.banner(action), .exit], "\(letter)")
        #expect(!n.on)
    }
    for (letter, action) in [("n", ChordAction.next), ("j", .next), ("p", .previous), ("k", .previous)] {
        var n = onWithBanner()
        #expect(n.handle(.key(.letter(letter)), now: 5).actions == [.banner(action)], "\(letter)")
        #expect(n.on, "\(letter) keeps the mode")
    }
}

@Test func bannerVerbsIgnoredWithoutBanner() {
    var n = on()
    let r = n.handle(.key(.letter("o")), now: 5)
    #expect(r.swallow && r.actions.isEmpty && n.on)
    play(&n, [.banner(up: true), .banner(up: false)], from: 6)
    #expect(n.handle(.key(.letter("x")), now: 9).actions.isEmpty)
}

@Test func popupVerbsWinOverBanner() {
    var n = onWithBanner()
    play(&n, [.key(.letter("c"))], from: 5)
    #expect(n.handle(.key(.letter("x")), now: 7).actions == [.remove])
    #expect(n.handle(.key(.letter("o")), now: 8).actions == [.choose, .exit])
}

@Test func snoozeSettlesAfterPause() {
    var n = onWithBanner()
    #expect(n.handle(.key(.letter("z")), now: 5).actions.isEmpty)
    #expect(n.snoozePreview == 3)
    #expect(n.handle(.key(.letter("z")), now: 5.3).actions.isEmpty)
    #expect(n.snoozePreview == 5)
    #expect(n.handle(.tick, now: 5.9).actions.isEmpty)
    #expect(n.handle(.tick, now: 6.0).actions == [.banner(.snooze(minutes: 5)), .exit])
    #expect(!n.on && n.snoozePreview == nil)
}

@Test func snoozeLadderStopsAtThirty() {
    var n = onWithBanner()
    play(&n, Array(repeating: .key(.letter("z")), count: 6), from: 5)
    #expect(n.snoozePreview == 30)
}

@Test func snoozeSettlesOnHeldLeaderUp() {
    var n = KeyNav()
    play(&n, [.banner(up: true), .leaderDown(three), .key(.letter("z")), .tick])  // a tick while held waits for the release
    #expect(n.snoozePreview == 3)
    #expect(n.handle(.leaderUp, now: 9).actions == [.banner(.snooze(minutes: 3)), .exit])
}

@Test func escCancelsSnooze() {
    var n = onWithBanner()
    play(&n, [.key(.letter("z")), .key(.esc)], from: 5)
    #expect(n.snoozePreview == nil && n.on)
    #expect(n.handle(.tick, now: 20).actions.isEmpty)
}

@Test func bannerGoneCancelsSnooze() {
    var n = onWithBanner()
    play(&n, [.key(.letter("z")), .banner(up: false)], from: 5)
    #expect(n.snoozePreview == nil)
    #expect(n.handle(.tick, now: 20).actions.isEmpty)
}

@Test func remappedVerbsLeaveHints() {
    let verbs = Verbs(open: "e", dismiss: "q")
    var n = KeyNav(verbs: verbs)
    play(&n, [.banner(up: true), .leaderDown(three), .leaderUp])
    #expect(!n.hints.values.contains { $0.contains("e") || $0.contains("q") })
    #expect(n.handle(.key(.letter("e")), now: 5).actions == [.banner(.open), .exit])
    for count in [15, 60] {
        let labels = KeyNav.labels(count: count, chars: KeyNav.hintChars(KeyNav.defaultHintChars, verbs: verbs))
        #expect(labels.allSatisfy { !$0.contains("e") && !$0.contains("q") })
    }
}

// MARK: - A lone modifier as the leader

@Test func modifierLeaderTapToggles() {
    var n = KeyNav(modifierLeader: true)
    let down = n.handle(.leaderDown(three), now: 0)
    #expect(!down.swallow && !n.on)  // the modifier reaches the apps; nothing is decided yet
    #expect(!n.handle(.leaderUp, now: 1).swallow)
    #expect(n.on && n.hints.count == 3)
    play(&n, [.leaderDown(three), .leaderUp], from: 2)
    #expect(!n.on)
}

@Test func modifierLeaderHeldVerbIsChord() {
    var n = KeyNav(modifierLeader: true)
    play(&n, [.banner(up: true), .leaderDown(three)])
    let r = n.handle(.key(.letter("o")), now: 5)
    #expect(r.swallow && r.actions == [.banner(.open)])
    #expect(n.handle(.leaderUp, now: 6).actions.isEmpty)
    #expect(!n.on)

    var z = KeyNav(modifierLeader: true)
    play(&z, [.banner(up: true), .leaderDown(three), .key(.letter("z")), .key(.letter("z"))])
    #expect(z.handle(.leaderUp, now: 9).actions == [.banner(.snooze(minutes: 5))])
    #expect(!z.on)
}

@Test func modifierLeaderHeldOtherKeyPasses() {
    for key in [NavKey.letter("h"), .letter("q"), .modified, .enter] {
        var n = KeyNav(modifierLeader: true)
        play(&n, [.banner(up: true), .leaderDown(three)])
        #expect(!n.handle(.key(key), now: 5).swallow, "\(key)")
        play(&n, [.leaderUp], from: 6)
        #expect(!n.on, "\(key): someone else's shortcut, no mode")
    }
}

@Test func modifierLeaderHeldInModeIsAKeyOfTheMode() {
    var n = KeyNav(modifierLeader: true)
    play(&n, [.leaderDown(three), .leaderUp, .leaderDown(three)])
    #expect(n.handle(.key(.letter("c")), now: 5).actions == [.open("widget:audio")])
    play(&n, [.leaderUp], from: 6)
    #expect(n.on && n.popup == "widget:audio")
}

@Test func cliOnTurnsItOnWithoutALeader() {
    var n = KeyNav()
    let r = n.handle(.on(three), now: 0)
    #expect(!r.swallow && n.on && n.hints.count == 3)
    _ = n.handle(.on(three), now: 25)  // a repeated on does not hold the mode open
    #expect(n.expired(now: 30))
}

@Test func previewVerbs() {
    var n = KeyNav(context: .preview)
    for c in ["c", "m", "s", "t"] {
        let r = n.handle(.key(.letter(c)), now: 0)
        #expect(r.swallow && r.actions == [.preview(c)])
    }
    for k in [NavKey.enter, .letter("o")] { #expect(n.handle(.key(k), now: 0) == (true, [.choose])) }
    #expect(n.handle(.key(.esc), now: 0) == (true, [.exit]))
    for k in [NavKey.letter("q"), .letter("j"), .modified, .other] { #expect(n.handle(.key(k), now: 0) == (false, [])) }
}

@Test func previewNeedsNoLeaderAndIgnoresIt() {
    var n = KeyNav(context: .preview)
    #expect(n.handle(.leaderDown(three), now: 0) == (false, []))
    #expect(!n.on)
}

@Test func armageddonOnlyOpens() {
    var n = KeyNav(context: .armageddon, verbs: Verbs(open: "e"))
    for k in [NavKey.enter, .letter("e")] { #expect(n.handle(.key(k), now: 0) == (true, [.choose])) }
    for k in [NavKey.letter("x"), .letter("o"), .esc, .modified] { #expect(n.handle(.key(k), now: 0) == (false, [])) }
}

@Test func popupAltFollowsRemappedVerb() {
    var n = KeyNav(verbs: Verbs(alt: "e"))
    play(&n, [.leaderDown(three), .leaderUp, .key(.letter("c"))])
    #expect(n.handle(.key(.letter("e")), now: 9) == (true, [.alt]))
    #expect(n.handle(.key(.letter("a")), now: 9) == (true, []))
    #expect(n.popup == "widget:audio")
}

@Test func settingsVerbs() {
    var n = KeyNav(context: .settings)
    let cases: [(NavKey, [NavAction])] = [
        (.letter("h"), [.side(-1)]), (.left, [.side(-1)]), (.letter("l"), [.side(1)]), (.right, [.side(1)]),
        (.letter("j"), [.move(1)]), (.down, [.move(1)]), (.letter("k"), [.move(-1)]), (.up, [.move(-1)]),
        (.enter, [.choose]), (.letter("o"), [.choose]), (.esc, [.exit]),
    ]
    for (key, want) in cases { #expect(n.handle(.key(key), now: 0) == (true, want), "\(key)") }
    for k in [NavKey.letter("x"), .letter("c"), .modified, .other] { #expect(n.handle(.key(k), now: 0) == (false, [])) }
}
