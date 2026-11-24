import Testing
@testable import GzymsCore

private let rows = ["Permissions grants accessibility", "Do Not Disturb on dnd", "Test banner notification", "Sounds audio",
                    "Slack · Krzysztof Nowak · deploy done", "Slack · Anna · lunch?", "Quit gzyms"]

private func rank(_ q: String) -> [String] { paletteRank(q, rows) { $0 } }

@Test func wordStartsAndLettersInOrderFit() {
    #expect(rank("perm").first == "Permissions grants accessibility")
    #expect(rank("dnd").first == "Do Not Disturb on dnd")
    #expect(rank("tst bnr") == ["Test banner notification"])
    #expect(rank("quit") == ["Quit gzyms"])
}

@Test func everyWordMustFitAndNotificationsMatchAppAndSender() {
    #expect(rank("slack krzysz") == ["Slack · Krzysztof Nowak · deploy done"])
    #expect(rank("slack").count == 2)
    #expect(rank("slack zzz").isEmpty)
    #expect(rank("xyz").isEmpty)
}

@Test func titleBeatsAMentionLaterAndEmptyKeepsAll() {
    #expect(paletteRank("sound", ["Banner with sound", "Sounds audio"]) { $0 } == ["Sounds audio", "Banner with sound"])
    #expect(rank("") == rows)
    #expect(rank("  ") == rows)
}

@Test func minutesFromTheQueryForDNDAndCaffeine() {
    #expect(paletteMinutes("dnd 1h", after: "dnd") == 60)
    #expect(paletteMinutes("DND 30", after: "dnd") == 30)
    #expect(paletteMinutes("dnd 45m", after: "dnd") == 45)
    #expect(paletteMinutes("dnd 1h30", after: "dnd") == 90)
    #expect(paletteMinutes("dnd 0", after: "dnd") == nil)
    #expect(paletteMinutes("dnd h", after: "dnd") == nil)
    #expect(paletteMinutes("dnd", after: "dnd") == nil)
    #expect(paletteMinutes("dnd soon", after: "dnd") == nil)
    #expect(paletteMinutes("caffeine 30m", after: "caffeine") == 30)
    #expect(paletteMinutes("Caffeine 2h", after: "caffeine") == 120)
    #expect(paletteMinutes("caffeine 30m", after: "dnd") == nil)
    #expect(paletteMinutes("dnd 30m", after: "caffeine") == nil)
}

@Test func spansAndMeetingTimesInWords() {
    #expect(paletteSpan(45) == "45 min")
    #expect(paletteSpan(60) == "1 h")
    #expect(paletteSpan(90) == "1 h 30 min")
    #expect(paletteSpan(120) == "2 h")
    #expect(paletteWhen(start: 1000, now: 1000) == "now")
    #expect(paletteWhen(start: 1000 + 25 * 60, now: 1000) == "in 25 min")
    #expect(paletteWhen(start: 1000 + 150 * 60, now: 1000) == "in 2 h 30 min")
    #expect(paletteWhen(start: 1000, now: 1000 + 10 * 60) == "10 min ago")
}

/// With hundreds of rows the top must stay sensible: a word start beats letters in order, and on an equal score
/// a Settings row or action (tier 0) goes before a plugin row (tier 2).
@Test func wordStartsBeatLettersInOrderAndTiersBreakTies() {
    #expect(paletteRank("bat", ["Basket sync", "Stop on battery under"]) { $0 } == ["Stop on battery under", "Basket sync"])
    let rows = [("Sounds from a plugin", 2), ("Sounds", 0)]
    #expect(paletteRank("sounds", rows, tier: { $0.1 }) { $0.0 }.map(\.0) == ["Sounds", "Sounds from a plugin"])
    // A better score still wins over a better tier.
    #expect(paletteRank("deploy", [("Open deploy log", 0), ("Deploy staging", 2)], tier: { $0.1 }) { $0.0 }.map(\.0) == ["Deploy staging", "Open deploy log"])
}

/// Greg's live test: "battery" is only a keyword of the General tab but in the title of the setting.
@Test func aTitleFitBeatsAKeywordOnlyFitWhateverTheTier() {
    let rows = [("General", "workspaces caffeine display awake battery config", 0), ("Stop on battery under", "Caffeine awake settings", 1)]
    #expect(paletteRank("battery", rows, tier: { $0.2 }, words: { $0.1 }) { $0.0 }.map(\.0) == ["Stop on battery under", "General"])
    // Same kind of fit (both keywords only): the tab goes first.
    #expect(paletteRank("caffeine", rows, tier: { $0.2 }, words: { $0.1 }) { $0.0 }.map(\.0) == ["General", "Stop on battery under"])
}

/// The rows come from the pills after `linkAgents`: a PR row with an agent on its branch opens it on ⌘Enter, like `a`.
@Test func aRowWithAnAgentOnItsBranchOpensTheAgentOnAlt() {
    let br = RepoBranch(repo: "greg/gzyms", branch: "feat/marks")
    let pr = PluginPill(plugin: "gh-prs", item: PluginItem(id: "prs", text: "PRs", menu: [PluginRow(id: "pr:29", text: "Palette", branch: br),
                                                                                         PluginRow(id: "pr:30", text: "Other")]))
    let agent = Agent(source: .tuios, id: "42a9cdac", name: "palette", place: "gzyms", state: .working, branch: br)
    let rows = palettePluginRows(linkAgents([pr], agents: [agent]), skip: agentsPill)
    #expect(rows[0].alt == .agent(agent.key) && rows[0].opensAgent)
    #expect(rows[1].alt == nil && !rows[1].opensAgent)
    // Another second action (a row of another plugin) keeps it and the plain kind.
    #expect(!PalettePluginRow(plugin: "gh-builds", id: "b", title: "b", words: "", alt: .row(plugin: "gh-prs", id: "pr:29")).opensAgent)
}

@Test func pluginRowsWithAnIdBecomePaletteRows() {
    let menu = [PluginRow(headline: RowHeadline(value: "42")),
                PluginRow(id: "chart", text: "chart", chart: RowChart(values: [1, 2])),
                PluginRow(id: "stats", text: "stats", stats: [RowStat(label: "a", value: "1")]),
                PluginRow(text: "Open PRs"),
                PluginRow(separator: true),
                PluginRow(id: "pr-1", text: "Fix the banner", tag: "#12", detail: "CI passed"),
                PluginRow(id: "pr-1", text: "Fix the banner again"),
                PluginRow(id: "meter", text: "Disk", meter: RowMeter(value: 3, max: 5))]
    var withAlt = PluginRow(id: "pr-2", text: "Add marks")
    withAlt.alt = .agent("claude:abc")
    let pills = [PluginPill(plugin: "gh-prs", item: PluginItem(id: "prs", text: "PRs 2", menu: menu + [withAlt])),
                 PluginPill(plugin: "agents", item: PluginItem(id: "agents", text: "1", menu: [PluginRow(id: "tuios:1", text: "claude")]))]
    let rows = palettePluginRows(pills, skip: "agents")
    #expect(rows.map(\.id) == ["pr-1", "meter", "pr-2"])
    #expect(rows[0] == PalettePluginRow(plugin: "gh-prs", id: "pr-1", title: "Fix the banner", words: "#12 CI passed PRs 2", alt: nil))
    #expect(rows[2].alt == .agent("claude:abc"))
}

@Test func spaceOpensThePaletteAndEndsTheMode() {
    var n = KeyNav()
    _ = n.handle(.leaderDown([]), now: 0)
    _ = n.handle(.leaderUp, now: 0)
    #expect(NavKey(keyCode: 49, modified: false) == .space)
    let r = n.handle(.key(.space), now: 1)
    #expect(r.swallow && r.actions == [.palette, .exit])
    #expect(!n.on)
}
