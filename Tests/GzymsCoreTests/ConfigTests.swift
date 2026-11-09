import Testing
@testable import GzymsCore

@Test func missingFileGivesDefaults() {
    #expect(loadConfig(toml: nil) == ConfigLoad(config: .defaults, problems: []))
}

@Test func defaultsUseGregsWorkspaceMap() {
    #expect(GzymsConfig.defaults.workspaces == WorkspaceStyle.gregDefaults)
    #expect(GzymsConfig.defaults.showEmpty == false)
    #expect(GzymsConfig.defaults.smallOnNotch == false)  // Greg, 2026-10-31: the small variant was hard to read
}

@Test func overridesOneColour() {
    let load = loadConfig(toml: """
    [[workspaces.style]]
    number = 2
    color = "#FF0000"
    """)
    #expect(load.problems == [])
    #expect(load.config.workspaces[1].color == "#FF0000")
    #expect(load.config.workspaces[1].name == "term")
    #expect(load.config.workspaces[0] == WorkspaceStyle.gregDefaults[0])
}

@Test func badColourKeepsDefaultAndReportsIt() {
    let load = loadConfig(toml: """
    [[workspaces.style]]
    number = 2
    color = "orange"
    """)
    #expect(load.config.workspaces[1].color == "peach")
    #expect(load.problems.contains { $0.contains("workspaces.style[2].color") })
}

@Test func workspaceColourCanBeAThemeToken() {
    let load = loadConfig(toml: "[[workspaces.style]]\nnumber = 2\ncolor = \"sky\"")
    #expect(load.problems == [])
    #expect(load.config.workspaces[1].color == "sky")
}

@Test func themeIsPickedByName() {
    #expect(GzymsConfig.defaults.theme == .mochaNeon)
    #expect(loadConfig(toml: "theme = \"grayscale\"").config.theme == .grayscale)
    let bad = loadConfig(toml: "theme = \"solarized\"")
    #expect(bad.config.theme == .mochaNeon)
    #expect(bad.problems.contains { $0.contains("theme") && $0.contains("gzyms theme --list") })
}

@Test func cpuChartIsLineOrBars() {
    #expect(GzymsConfig.defaults.cpuChart == .line)
    #expect(loadConfig(toml: "[cpu]\nchart = \"bars\"").config.cpuChart == .bars)
    let bad = loadConfig(toml: "[cpu]\nchart = \"pie\"")
    #expect(bad.config.cpuChart == .line)
    #expect(bad.problems.contains { $0.contains("cpu.chart") })
}

@Test func unknownKeyIsReportedNotFatal() {
    let load = loadConfig(toml: """
    [workspaces]
    shw_empty = true
    """)
    #expect(load.config == .defaults)
    #expect(load.problems.contains { $0.contains("workspaces.shw_empty") })
}

@Test func showEmptyCanBeTurnedOn() {
    #expect(loadConfig(toml: "[workspaces]\nshow_empty = true").config.showEmpty == true)
}

@Test func brokenTomlGivesDefaultsAndOneProblem() {
    let load = loadConfig(toml: "[[[ nope")
    #expect(load.config == .defaults)
    #expect(load.problems.count == 1)
    #expect(load.broken)
    #expect(!loadConfig(toml: "theme = 3").broken)
}

@Test func soundsDefaultOn() {
    #expect(GzymsConfig.defaults.notificationSounds)
}

@Test func soundsCanBeTurnedOff() {
    let load = loadConfig(toml: "[notifications]\nsounds = false")
    #expect(load.problems == [])
    #expect(load.config.notificationSounds == false)
}

@Test func unknownNotificationsKeyIsReported() {
    let load = loadConfig(toml: "[notifications]\nloud = true")
    #expect(load.problems == ["notifications.loud: unknown key, ignored"])
}

@Test func oldBannerKeysAreStillReadAndReportedOnce() {
    let load = loadConfig(toml: "[notifications]\nkeys = \"chord\"\nhold = \"f18\"\n\n[notifications.letters]\nopen = \"e\"\n")
    #expect(load.config.leader == .key(code: 79, name: "f18"))
    #expect(load.config.verbs == Verbs(open: "e"))
    #expect(load.problems.count == 1)
    let p = load.problems.first ?? ""
    #expect(p.contains("notifications.hold") && p.contains("notifications.keys") && p.contains("notifications.letters"))
    #expect(p.contains("leader = \"f18\"") && p.contains("[keys.verbs]") && p.contains("open = \"e\""))

    // The new keys win; the old ones are only reported.
    let both = loadConfig(toml: "[keys]\nleader = \"f19\"\n\n[keys.verbs]\nopen = \"q\"\n\n[notifications]\nhold = \"cmd\"\n\n[notifications.letters]\nopen = \"e\"\n")
    #expect(both.config.leader == .key(code: 80, name: "f19") && both.config.verbs == Verbs(open: "q"))
    #expect(both.problems.count == 1)

    #expect(loadConfig(toml: "[notifications]\nhold = \"ctrl\"").config.leader == .modifier("ctrl"))
    #expect(loadConfig(toml: "[notifications]\nhold = \"capslock\"").config.leader == GzymsConfig.defaults.leader)
}

@Test func levelTimesAreSecondsAndZeroMeansUntilClicked() {
    let load = loadConfig(toml: "[notifications.levels]\ninfo = 30\nwarning = 0\nerror = 4.5\n")
    #expect(load.problems == [])
    #expect(load.config.levelSeconds[.info] == 30)
    #expect(load.config.levelSeconds[.warning] == .some(nil))
    #expect(load.config.levelSeconds[.error] == 4.5)
    #expect(load.config.levelSeconds[.critical] == .some(nil))
}

@Test func badLevelTimesKeepTheDefault() {
    let load = loadConfig(toml: "[notifications.levels]\ninfo = -3\narmageddon = 5\n")
    #expect(load.config.levelSeconds == NotifyLevel.defaultSeconds)
    #expect(load.problems.count == 2)
    #expect(load.problems.contains { $0.hasPrefix("notifications.levels.info") })
    // Critical may hide too if the user wants it (Greg); only armageddon always waits.
    #expect(loadConfig(toml: "[notifications.levels]\ncritical = 30\n").config.levelSeconds[.critical] == 30)
    #expect(load.problems.contains { $0.hasPrefix("notifications.levels.armageddon") })
}

@Test func perAppRulesAreKeyedByBundleID() {
    let toml = """
    [notifications.apps."com.tinyspeck.slackmacgap"]
    sound = false
    level = "armageddon"
    """
    let load = loadConfig(toml: toml)
    #expect(load.problems == [])
    #expect(load.config.appRules == ["com.tinyspeck.slackmacgap": AppRule(banner: true, sound: false, count: true, level: .armageddon)])
    let bad = loadConfig(toml: "[notifications.apps.\"a.b\"]\nlevel = \"loud\"\nwhat = 1\n")
    #expect(bad.config.appRules["a.b"]?.level == .normal)
    #expect(bad.problems.count == 2)
}

@Test func verbsAreSevenDifferentLettersOutsideHJKLF() {
    #expect(GzymsConfig.defaults.verbs == Verbs())
    let load = loadConfig(toml: "[keys.verbs]\nopen = \"e\"\nsnooze = \"s\"\nnext = \"m\"\nclear = \"c\"\n")
    #expect(load.problems == [])
    #expect(load.config.verbs == Verbs(open: "e", snooze: "s", next: "m", clear: "c"))
    for bad in ["next = \"o\"", "prev = \"n\"", "open = \"x\"", "open = \"oo\"", "open = \"j\"", "open = \"f\"", "open = \"1\"",
                "clear = \"x\"", "open = \"d\""] {
        let load = loadConfig(toml: "[keys.verbs]\n" + bad)
        #expect(load.config.verbs == Verbs(), "\(bad)")
        #expect(load.problems.count == 1 && load.problems[0].hasPrefix("keys.verbs"), "\(bad): \(load.problems)")
    }
    #expect(loadConfig(toml: "[keys.verbs]\nloud = \"q\"").problems == ["keys.verbs.loud: unknown key, ignored"])
}

@Test func hintCharsLeaveRemappedVerbsOut() {
    let load = loadConfig(toml: "[keys]\nhint_chars = \"bcde\"\n\n[keys.verbs]\nopen = \"e\"\n")
    #expect(load.config.hintChars == "bc")  // e is open, d is clear
    #expect(load.problems.count == 1)
}

@Test func appearanceAndDeviceIcons() {
    #expect(GzymsConfig.defaults.animations && GzymsConfig.defaults.followReduceMotion)
    let load = loadConfig(toml: "[appearance]\nanimations = false\n\n[audio.icons]\n\"Shure MV7\" = \"external\"\n\"Desk\" = \"toaster\"\n")
    #expect(!load.config.animations)
    #expect(load.config.deviceIcons == ["Shure MV7": .external])
    #expect(load.problems.count == 1)
}

@Test func bannerEntryAndSpeed() {
    #expect(GzymsConfig.defaults.bannerEntry == .drop && GzymsConfig.defaults.animationSpeed == .normal)
    let load = loadConfig(toml: "[appearance]\nbanner_entry = \"notch\"\nanimation_speed = \"fast\"\n")
    #expect(load.config.bannerEntry == .notch && load.config.animationSpeed == .fast && load.problems.isEmpty)
    let bad = loadConfig(toml: "[appearance]\nbanner_entry = \"spin\"\nanimation_speed = \"warp\"\n")
    #expect(bad.config.bannerEntry == .drop && bad.config.animationSpeed == .normal && bad.problems.count == 2)
    #expect(AnimationSpeed.slow.factor > 1 && AnimationSpeed.fast.factor < 1)
}

/// Greg's order: animations off beats Reduce motion (a fade), which beats the chosen style.
@Test func bannerEntryUnderReduceMotionAndOff() {
    var c = GzymsConfig.defaults
    c.bannerEntry = .pop
    #expect(c.entry(reduceMotion: false) == .pop && c.animates(reduceMotion: false))
    #expect(c.entry(reduceMotion: true) == .fade && !c.animates(reduceMotion: true))
    c.followReduceMotion = false
    #expect(c.entry(reduceMotion: true) == .pop && c.animates(reduceMotion: true))
    c.animations = false
    #expect(c.entry(reduceMotion: false) == nil && c.entry(reduceMotion: true) == nil && !c.animates(reduceMotion: false))
}

@Test func bannedAudioDevicesByName() {
    #expect(GzymsConfig.defaults.bannedDevices.isEmpty)
    let load = loadConfig(toml: "[audio]\nbanned = [\"Alex iPhone  Microphone\"]\n\n[audio.icons]\n\"Desk\" = \"mic\"\n")
    #expect(load.config.bannedDevices == ["Alex iPhone  Microphone"])
    #expect(load.config.deviceIcons == ["Desk": .mic])
    #expect(load.problems.isEmpty)
    #expect(load.config.bansIPhone)
    #expect(!loadConfig(toml: "[audio]\nbanned = [\"Insta360 Link 2\"]\n").config.bansIPhone)
}

@Test func menuBarKeyIsAModifierOrOff() {
    #expect(GzymsConfig.defaults.menuBarKey == .cmd)
    #expect(loadConfig(toml: "[bar]\nmenu_bar_key = \"off\"").config.menuBarKey == .off)
    let bad = loadConfig(toml: "[bar]\nmenu_bar_key = \"f18\"")
    #expect(bad.config.menuBarKey == .cmd)
    #expect(bad.problems.count == 1)
}

@Test func layoutKeepsTheUsersSidesAndAddsTheRest() {
    let installed = ["pr-watch", "hello"]
    #expect(barLayout(left: nil, right: nil, plugins: installed) == .recommended(plugins: installed))
    #expect(BarLayoutPlan.recommended(plugins: installed).left == [.plugin("hello"), .plugin("pr-watch")])
    // cpu moved left, pr-watch moved right, a removed plugin and a duplicate dropped, the rest on its recommended side
    let p = barLayout(left: ["cpu", "plugin:gone"], right: ["plugin:pr-watch", "clock", "cpu"], plugins: installed)
    #expect(p.left == [.widget(.cpu), .plugin("hello")])
    #expect(Array(p.right.prefix(2)) == [.plugin("pr-watch"), .widget(.clock)])
    #expect(!p.right.contains(.widget(.cpu)) && p.right.count == BarWidget.allCases.count)  // all built-ins but cpu, plus pr-watch
    #expect(BarSlot("plugin:x")?.name == "plugin:x" && BarSlot("nope") == nil && BarSlot("plugin:") == nil)

    let l = loadConfig(toml: "[widgets]\nleft = [\"cpu\"]\norder = [\"clock\", \"nope\"]\nmusic = false")
    #expect(l.config.layoutLeft == ["cpu"] && l.config.layoutRight == ["clock", "nope"])
    #expect(l.config.hiddenWidgets == [.music])
    #expect(l.problems.count == 1)  // "nope"
    #expect(loadConfig(toml: "[widgets]\norder = 3").problems.count == 1)
}

@Test func barLogoIsAPathOrTheCat() {
    #expect(GzymsConfig.defaults.logo == nil)
    let l = loadConfig(toml: "[bar]\nlogo = \"~/Pictures/unicorn.svg\"")
    #expect(l.config.logo == "~/Pictures/unicorn.svg")
    #expect(l.problems.isEmpty)
    #expect(loadConfig(toml: "[bar]\nlogo = \"\"").config.logo == nil)
}

@Test func meetingPointsAreSomeOfFiveThreeZeroMinusThree() {
    #expect(GzymsConfig.defaults.meetingPoints == [3])
    #expect(loadConfig(toml: "[calendar]\npoints = [0, 5]").config.meetingPoints == [5, 0])
    let bad = loadConfig(toml: "[calendar]\npoints = [10]")
    #expect(bad.config.meetingPoints == [3])
    #expect(bad.problems.count == 1)
    #expect(!loadConfig(toml: "[calendar]\nenabled = false").config.calendarEnabled)
    let skip = loadConfig(toml: "[calendar]\nskip = [\"iCloud/Birthdays\", \"Work/Holidays\"]")
    #expect(skip.config.calendarSkip == ["iCloud/Birthdays", "Work/Holidays"])
    #expect(skip.problems.isEmpty)
    #expect(setting("skip", to: .strings(["a/b", "c\"d"]), in: .table(["calendar"]), toml: nil).contains("skip = [\"a/b\", \"c\\\"d\"]"))
}

@Test func widgetsCanBeTurnedOff() {
    let load = loadConfig(toml: "[widgets]\ncpu = false\nclock = true\nweather = false\n")
    #expect(load.config.hiddenWidgets == [.cpu])
    #expect(load.problems.count == 1)
}

@Test func keysLeaderIsAnFKeyAChordOrOff() {
    #expect(GzymsConfig.defaults.leader == .chord(Shortcut("ctrl+alt+g")!))
    #expect(loadConfig(toml: "[keys]\nleader = \"f19\"").config.leader == .key(code: 80, name: "f19"))
    #expect(loadConfig(toml: "[keys]\nleader = \"F1\"").config.leader == .key(code: 122, name: "f1"))
    #expect(loadConfig(toml: "[keys]\nleader = \"ctrl+alt+k\"").config.leader == .chord(Shortcut("ctrl+alt+k")!))
    #expect(loadConfig(toml: "[keys]\nleader = \"off\"").config.leader == nil)
    for m in ["ctrl", "alt", "cmd"] { #expect(loadConfig(toml: "[keys]\nleader = \"\(m)\"").config.leader == .modifier(m)) }
    #expect(Leader("option") == .modifier("alt") && Leader("shift") == nil)
    #expect(Leader("f19")?.text == "f19" && Leader("ctrl")?.text == "ctrl" && Leader("ctrl+alt+g")?.text == "ctrl+alt+g")
    #expect(Leader("f19")?.symbol == "F19" && Leader("ctrl")?.symbol == "⌃ Ctrl" && Leader("ctrl+alt+g")?.symbol == "⌃⌥G")
    let bad = loadConfig(toml: "[keys]\nleader = \"hyper\"")
    #expect(bad.config.leader == GzymsConfig.defaults.leader)
    #expect(bad.problems.contains { $0.contains("keys.leader") })
}

@Test func keysIdleTimeout() {
    #expect(GzymsConfig.defaults.idleTimeout == 30)
    #expect(loadConfig(toml: "[keys]\nidle_timeout = 0").config.idleTimeout == 0)
    #expect(loadConfig(toml: "[keys]\nidle_timeout = 12.5").config.idleTimeout == 12.5)
    let bad = loadConfig(toml: "[keys]\nidle_timeout = -1")
    #expect(bad.config.idleTimeout == 30 && bad.problems.contains { $0.contains("keys.idle_timeout") })
}

@Test func keysHintCharsDropVerbs() {
    #expect(GzymsConfig.defaults.hintChars == KeyNav.defaultHintChars)
    let some = loadConfig(toml: "[keys]\nhint_chars = \"asdfgqwer\"")
    #expect(some.config.hintChars == "sgqwer")
    #expect(some.problems.contains { $0.contains("keys.hint_chars") })
    let short = loadConfig(toml: "[keys]\nhint_chars = \"hjkx\"")
    #expect(short.config.hintChars == KeyNav.defaultHintChars)
}

@Test func keysUnknownKeyIsReported() {
    #expect(loadConfig(toml: "[keys]\nleadr = \"f19\"").problems.contains { $0.contains("keys.leadr") })
}

@Test func openOriginalIsOnUnlessTurnedOff() {
    #expect(loadConfig(toml: nil).config.openOriginal)
    let off = loadConfig(toml: "[notifications]\nopen_original = false")
    #expect(!off.config.openOriginal)
    #expect(off.problems.isEmpty)
}

@Test func bannerAXAndSignalDefaultOnAndParse() {
    #expect(loadConfig(toml: nil).config.bannerAX)
    #expect(loadConfig(toml: nil).config.signal)
    let off = loadConfig(toml: "[notifications]\nbanner_ax = false\nsignal = false\n")
    #expect(!off.config.bannerAX)
    #expect(!off.config.signal)
    #expect(off.problems.isEmpty)
}

@Test func ncAutoRestartDefaultsOffAndParses() {
    #expect(!loadConfig(toml: nil).config.ncAutoRestart)
    let on = loadConfig(toml: "[notifications]\nnc_auto_restart = true\n")
    #expect(on.config.ncAutoRestart)
    #expect(on.problems.isEmpty)
}

@Test func quietSharingDefaultsOnAndParses() {
    #expect(loadConfig(toml: nil).config.quietSharing)
    let off = loadConfig(toml: "[notifications]\nquiet_sharing = false\n")
    #expect(!off.config.quietSharing)
    #expect(off.problems.isEmpty)
}
