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
    #expect(n.hints == ["ws:1": "b", "widget:audio": "c", "bell": "e"])  // d is the clear verb
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
            #expect(l.allSatisfy { !"hjklxazfonpd".contains($0) })
        }
    }
    #expect(!KeyNav.hintChars("bcde", verbs: Verbs()).contains("d"))
}

@Test func ddInAPopupClearsAll() {
    var n = on()
    play(&n, [.key(.letter("e"))])  // the bell's list
    let first = n.handle(.key(.letter("d")), now: 5)
    #expect(first.swallow && first.actions.isEmpty)
    #expect(n.handle(.key(.letter("d")), now: 5.5).actions == [.clearAll])
    #expect(n.on && n.popup == "bell")
    #expect(n.handle(.key(.letter("d")), now: 5.6).actions.isEmpty, "a third d starts over")
}

@Test func ddNeedsTwoQuickDsInARow() {
    var slow = on()
    play(&slow, [.key(.letter("e"))])
    #expect(play(&slow, [.key(.letter("d")), .key(.letter("d"))], from: 5) == [.clearAll], "one second apart is still in time")
    var late = on()
    play(&late, [.key(.letter("e"))])
    #expect(play(&late, [.key(.letter("d"))], from: 5).isEmpty)
    #expect(late.handle(.key(.letter("d")), now: 6.2).actions.isEmpty)
    var broken = on()
    play(&broken, [.key(.letter("e"))])
    #expect(play(&broken, [.key(.letter("d")), .key(.letter("j")), .key(.letter("d"))], from: 5) == [.move(1)])
}

@Test func ddTakesTheConfiguredLetter() {
    var n = KeyNav(verbs: Verbs(clear: "q"))
    play(&n, [.leaderDown(three), .leaderUp])
    play(&n, [.key(.letter(n.hints["bell"]!))])
    #expect(play(&n, [.key(.letter("q")), .key(.letter("q"))], from: 5) == [.clearAll])
}

@Test func dIsNotABannerVerb() {
    var n = onWithBanner()
    #expect(play(&n, [.key(.letter("d")), .key(.letter("d"))], from: 5).isEmpty)
    #expect(n.on)
}

@Test func ddWorksInAPopupTheMouseOpened() {
    var n = KeyNav()
    play(&n, [.popup("bell", three)])
    #expect(play(&n, [.key(.letter("d")), .key(.letter("d"))], from: 5) == [.clearAll])
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

@Test func hoverTakesTheShownLettersWithoutTheLeader() {
    for (letter, action) in [("o", ChordAction.open), ("x", .dismiss), ("a", .alt), ("n", .next)] {
        var n = KeyNav()
        play(&n, [.banner(up: true), .hover(true)])
        let r = n.handle(.key(.letter(letter)), now: 5)
        #expect(r.swallow && r.actions == [.banner(action)], "\(letter)")
        #expect(!n.on, "\(letter) does not turn the mode on")
    }
    var n = KeyNav()
    play(&n, [.banner(up: true), .hover(true)])
    #expect(n.handle(.key(.letter("z")), now: 5).swallow)
    #expect(n.handle(.tick, now: 5.8).actions == [.banner(.snooze(minutes: 3))])
    #expect(!n.handle(.key(.letter("j")), now: 6).swallow, "j is not shown")
    #expect(!n.handle(.key(.letter("e")), now: 6).swallow, "a hint letter is the bar's")
    #expect(!n.handle(.key(.modified), now: 6).swallow)
}

@Test func hoverOffOrBannerGoneOrModifierLeaderPassesLetters() {
    var n = KeyNav()
    play(&n, [.banner(up: true), .hover(true), .hover(false)])
    #expect(!n.handle(.key(.letter("o")), now: 5).swallow)
    play(&n, [.hover(true), .banner(up: false), .banner(up: true)], from: 6)
    #expect(!n.handle(.key(.letter("o")), now: 9).swallow, "a new banner needs a new hover")
    var m = KeyNav(modifierLeader: true)
    play(&m, [.banner(up: true), .hover(true)])
    #expect(!m.handle(.key(.letter("o")), now: 5).swallow, "its hints show the held chord")
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

@Test func mousePopupKeysTakeTheModeOn() {
    for (key, want) in [(NavKey.letter("j"), [NavAction.move(1)]), (.left, [.side(-1)]), (.letter("x"), [.remove]), (.esc, [.back])] {
        var n = KeyNav()
        play(&n, [.popup("widget:audio", three)])
        let r = n.handle(.key(key), now: 5)
        #expect(r.swallow && r.actions == want, "\(key)")
        #expect(n.on, "\(key)")
    }
    var n = KeyNav()
    play(&n, [.popup("widget:audio", three), .key(.letter("j"))])
    #expect(n.popup == "widget:audio")
    #expect(n.handle(.key(.enter), now: 9).actions == [.choose, .exit])
    #expect(!n.on && n.mouse == nil)
}

@Test func mousePopupLeavesOtherKeysAlone() {
    var n = KeyNav()
    play(&n, [.popup("widget:audio", three)])
    #expect(!n.handle(.key(.letter("q")), now: 5).swallow)
    #expect(!n.handle(.key(.modified), now: 5).swallow)
    #expect(!n.on)
    play(&n, [.popup(nil, three)])
    #expect(!n.handle(.key(.letter("j")), now: 9).swallow)
    play(&n, [.popup("bell", three), .off])
    #expect(!n.handle(.key(.letter("j")), now: 20).swallow)
}

@Test func mousePopupIdlesOut() {
    var n = KeyNav(idleTimeout: 30)
    play(&n, [.popup("bell", three), .key(.letter("j"))])
    #expect(n.on && !n.expired(now: 20) && n.expired(now: 31))
}
