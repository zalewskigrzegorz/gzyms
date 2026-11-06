import Foundation
import Testing
@testable import GzymsCore

private func d(_ s: String) -> Data { Data(s.utf8) }
private let at0 = Date(timeIntervalSince1970: 1_793_977_500)

// MARK: - Sources

@Test func tuiosAgentsReadsStatesAndFallsBackToThePrompt() throws {
    let json = #"{"agents":[{"window_id":"w1","session":"gzyms","state":"needs_input","needs_you":true,"name":"Fix","message":"approve rm"},"#
        + #"{"window_id":"w2","session":"dots","state":"working","needs_you":false,"name":"Build","message":"","meta":{"prompt":"make it"}},"#
        + #"{"window_id":"w3","session":"x","state":"done","needs_you":false,"name":"C"},{"window_id":"w4","state":"idle","name":"D"}]}"#
    let a = try tuiosAgents(stdout: d(json)).get()
    #expect(a.map(\.state) == [.waits, .working, .done, .idle])
    #expect(a.map(\.message) == ["approve rm", "make it", "", ""])
    #expect(a[0].key == "tuios:w1" && a[0].place == "gzyms" && a[0].target == "gzyms")
}

@Test func tuiosErrorsKeepTuiosWords() {
    let off = #"{"code":"agents_disabled","error":"Agent features are off. Set agents.enabled = true in the config to use this command.","success":false}"#
    #expect(tuiosAgents(stdout: d(off)) == .failure(AgentsError("Agent features are off. Set agents.enabled = true in the config to use this command.")))
    #expect(tuiosAgents(stdout: Data(), stderr: d(off)) == .failure(AgentsError("Agent features are off. Set agents.enabled = true in the config to use this command.")))
    #expect(tuiosAgents(stdout: Data(), stderr: d("connection refused\nmore")) == .failure(AgentsError("tuios: connection refused")))
    #expect(tuiosAgents(stdout: Data()) == .failure(AgentsError("tuios gave no answer.")))
}

@Test func tuiosBinaryLooksOnPathThenHomebrew() {
    #expect(tuiosBinary(path: "/a:/b") { $0 == "/b/tuios" } == "/b/tuios")
    #expect(tuiosBinary(path: nil) { $0 == "/opt/homebrew/bin/tuios" } == "/opt/homebrew/bin/tuios")
    #expect(tuiosBinary(path: "/a") { _ in false } == nil)
}

@Test func aClickMovesTheClientOnTheAgentsSessionElseAnyShowingOne() {
    let c = d(#"[{"client_id":"none","session":""},{"client_id":"other","session":"o"},{"client_id":"mine","session":"s1"}]"#)
    #expect(tuiosClient(c, session: "s1") == "mine")
    #expect(tuiosClient(c, session: "gone") == "other")
    #expect(tuiosClient(d(#"[{"client_id":"none","session":""}]"#), session: "s1") == nil)
}

private func file(_ id: String, state: String = "waits", pid: Int = 0, pane: String = "", term: String = "ghostty", entry: String = "cli") -> Data {
    d(#"{"id":"\#(id)","state":"\#(state)","since":1793977500,"pid":\#(pid),"transcript":"/t/\#(id).jsonl","cwd":"/Users/greg/Code/x","name":"x","message":"Claude needs your permission","tuios_pane":"\#(pane)","term":"\#(term)","entry":"\#(entry)"}"#)
}

@Test func claudeFilesParseAndGarbageIsSkipped() throws {
    let s = try #require(claudeSession(file("a")))
    #expect(s.state == .waits && s.since == at0 && s.name == "x" && s.transcript == "/t/a.jsonl")
    #expect(claudeSession(d(#"{"id":"a","state":"waits","si"#)) == nil)  // half written
    #expect(claudeSession(file("a", state: "thinking")) == nil)
    #expect(claudeSession(d(#"{"id":"b","state":"idle","since":1,"cwd":"/p/repo"}"#))?.name == "repo")
    #expect(claudeSession(d(#"{"id":"b","state":"idle","since":1,"cwd":"/p/repo","name":"repo","title":"Fix login"}"#))?.name == "Fix login")
    #expect(claudeSession(d(#"{"id":"b","state":"idle","since":1,"cwd":"/p/repo","name":"repo","title":""}"#))?.name == "repo")
}

@Test func aDesktopSessionSaysItRunsInClaudeDesktop() throws {
    let s = try #require(claudeSession(file("a", term: "", entry: "claude-desktop")))
    #expect(claudeAgents([s], tuiosOn: true, alive: { _ in true }, modified: { _ in nil }).agents.first?.place == "Claude Desktop")
}

@Test func deadSessionsGoAndAnAnswerWithoutAHookMeansIdle() throws {
    let sessions = try ["dead", "alive", "answered", "pane"].map { id in
        try #require(claudeSession(file(id, pid: id == "dead" ? 11 : 22, pane: id == "pane" ? "6f33" : "")))
    }
    let r = claudeAgents(sessions, tuiosOn: true, alive: { $0 != 11 },
                         modified: { $0 == "/t/answered.jsonl" ? at0 + 5 : $0 == "/t/alive.jsonl" ? at0 + 1 : nil })
    #expect(r.dead == ["dead"])
    #expect(r.agents.map(\.id) == ["alive", "answered"])  // the tuios pane is tuios's
    #expect(r.agents.map(\.state) == [.waits, .idle])
    #expect(r.agents[0].place == "x" && r.agents[0].target == "Ghostty" && r.agents[0].since == at0)
    // tuios off: the pane's session shows here.
    #expect(claudeAgents(sessions, tuiosOn: false, alive: { _ in true }, modified: { _ in nil }).agents.count == 4)
}

@Test func claudeAppFollowsTheTerminalOrTheDesktopApp() {
    #expect(claudeApp(term: "iTerm.app", entry: "cli") == "iTerm")
    #expect(claudeApp(term: "vscode", entry: "cli") == "Visual Studio Code")
    #expect(claudeApp(term: "", entry: "claude-desktop") == "Claude")
    #expect(claudeApp(term: "tmux", entry: "cli") == nil)
}

// MARK: - The pill

private func agent(_ id: String, _ state: AgentState, _ source: AgentSource = .tuios, message: String = "", since: Date? = nil) -> Agent {
    Agent(source: source, id: id, name: id, place: "s", state: state, message: message, since: since)
}

@Test func rowsSortWaitsDoneWorkingIdleAndIdleIsDim() {
    let looks: [AgentSource: AgentSourceLook] = [
        .tuios: AgentSourceLook(agents: [agent("i", .idle), agent("w", .working), agent("q", .waits, message: "approve?")]),
        .claude: AgentSourceLook(agents: [agent("d", .done, .claude), agent("b", .waits, .claude)]),
    ]
    let (item, failure) = agentsItem(looks)
    #expect(failure == nil)
    #expect(item.menu?.map(\.tag) == ["waits", "waits", "done", "working", "idle"])
    #expect(item.menu?.map(\.text) == ["b", "q · approve?", "d", "w", "i"])
    #expect(item.menu?.map(\.dim) == [false, false, false, false, true])
    #expect(item.text == "2" && item.color == "peach")
    #expect(agentsItem([.tuios: AgentSourceLook(agents: [agent("w", .working)])]).item.color == "sky")
    #expect(agentsItem([.tuios: AgentSourceLook()]).item.menu?.map(\.text) == ["No agents."])
}

@Test func aFailingSourceGreysOnlyItsOwnRows() {
    let broke = AgentSourceLook(agents: [agent("old", .waits)], problem: "Agent features are off.", since: at0)
    let (item, failure) = agentsItem([.tuios: broke, .claude: AgentSourceLook(agents: [agent("c", .working, .claude)])])
    #expect(failure == nil)
    #expect(item.menu?.first?.text == ":exclamationmark.triangle.fill@peach: tuios: Agent features are off.")
    #expect(item.menu?.dropFirst().map(\.dim) == [true, false])
    #expect(item.text == "1" && item.color == "sky")  // the old waiting one is not counted as fresh
    // Every source on fails: the whole pill greys out with what broke.
    let all = agentsItem([.tuios: broke])
    #expect(all.failure == PluginFailure(message: "Agent features are off.", since: at0))
    #expect(all.item.menu?.map(\.text) == ["old"])
}

@Test func settingsLineSaysTheStateInAFewWords() {
    let missing = ClaudePluginLook(state: .missing)
    #expect(agentSourceStatus(on: false, look: nil, plugin: missing) == AgentSourceStatus(line: "Off", plugin: missing))
    #expect(agentSourceStatus(on: true, look: AgentSourceLook(), plugin: missing) == AgentSourceStatus(line: "Not installed", notInstalled: true, plugin: missing))
    #expect(agentSourceStatus(on: true, look: nil, plugin: ClaudePluginLook(state: .noClaude)).line == "Claude Code not found")
    #expect(agentSourceStatus(on: true, look: AgentSourceLook(), plugin: ClaudePluginLook(state: .installed("0.1.1"))).line == "No agents")
    #expect(agentSourceStatus(on: true, look: AgentSourceLook(), plugin: ClaudePluginLook()).line == "No agents")  // not checked yet
    let off = "Agent features are off. Set agents.enabled = true in the config to use this command."
    #expect(agentSourceStatus(on: true, look: AgentSourceLook(problem: off)) == AgentSourceStatus(line: "Agent features are off", problem: off))
    #expect(agentSourceStatus(on: true, look: AgentSourceLook(agents: [agent("a", .idle)])).line == "1 agent")
    #expect(agentSourceStatus(on: true, look: nil).line == "Starting")
}

// MARK: - When to notify

@Test func theFirstLookOnlyLooksThenWaitsNotifiesOnceAndAnAnswerDismisses() {
    var w = AgentWatch()
    let id = AgentWatch.noteID("tuios:a")
    #expect(w.look(.tuios, [agent("a", .waits), agent("b", .working)], now: at0, doneAfter: 0) == ([], []))
    #expect(w.look(.tuios, [agent("a", .waits)], now: at0, doneAfter: 0) == ([], []))  // still waits, b left without a note
    var r = w.look(.tuios, [agent("a", .working)], now: at0, doneAfter: 0)
    #expect(r.dismiss.isEmpty && r.notify.isEmpty)  // the start-up wait had no note to take away
    r = w.look(.tuios, [agent("a", .waits, message: "approve rm")], now: at0, doneAfter: 0)
    #expect(r.notify.map(\.id) == [id] && r.notify.first?.title == "a waits for you" && r.notify.first?.body == "approve rm")
    #expect(r.notify.first?.level == .warning)
    #expect(w.look(.tuios, [agent("a", .waits)], now: at0, doneAfter: 0).notify.isEmpty)  // once
    r = w.look(.tuios, [agent("a", .working)], now: at0, doneAfter: 0)
    #expect(r.dismiss == [id] && r.notify.isEmpty)
    #expect(AgentWatch.key(noteID: id) == "tuios:a" && AgentWatch.key(noteID: "plugin:log-watcher:x") == nil)
}

@Test func aLongRunNotifiesDoneAShortOneDoesNot() {
    var w = AgentWatch()
    _ = w.look(.tuios, [], now: at0, doneAfter: 180)
    _ = w.look(.tuios, [agent("a", .working), agent("b", .working)], now: at0, doneAfter: 180)
    var r = w.look(.tuios, [agent("a", .done), agent("b", .working)], now: at0 + 60, doneAfter: 180)
    #expect(r.notify.isEmpty)
    r = w.look(.tuios, [agent("a", .done), agent("b", .idle)], now: at0 + 200, doneAfter: 180)
    #expect(r.notify.map(\.title) == ["b is done"] && r.notify.first?.body == "after 4 min" && r.notify.first?.level == .info)
    // Its note leaves when it works again, and when it leaves the bar.
    #expect(w.look(.tuios, [agent("a", .done), agent("b", .working)], now: at0 + 210, doneAfter: 180).dismiss == [AgentWatch.noteID("tuios:b")])
    _ = w.look(.tuios, [agent("b", .waits)], now: at0 + 220, doneAfter: 180)
    #expect(w.look(.tuios, [], now: at0 + 230, doneAfter: 180).dismiss == [AgentWatch.noteID("tuios:b")])
}

@Test func claudeRunsAreTimedByTheirOwnSince() {
    var w = AgentWatch()
    _ = w.look(.claude, [], now: at0, doneAfter: 180)
    _ = w.look(.claude, [agent("c", .working, .claude, since: at0)], now: at0 + 100, doneAfter: 180)
    let r = w.look(.claude, [agent("c", .done, .claude, since: at0 + 200)], now: at0 + 500, doneAfter: 180)
    #expect(r.notify.first?.body == "after 4 min")  // 200 s of work, not the 400 s between looks
}

@Test func aSourceTurnedOffTakesItsNotesAndLooksQuietlyWhenBack() {
    var w = AgentWatch()
    _ = w.look(.tuios, [], now: at0, doneAfter: 0)
    _ = w.look(.tuios, [agent("a", .waits)], now: at0, doneAfter: 0)
    _ = w.look(.claude, [], now: at0, doneAfter: 0)
    #expect(w.forget(.tuios) == [AgentWatch.noteID("tuios:a")])
    #expect(w.look(.tuios, [agent("a", .waits)], now: at0, doneAfter: 0).notify.isEmpty)
    #expect(w.look(.claude, [agent("c", .waits, .claude)], now: at0, doneAfter: 0).notify.count == 1)  // claude was not touched
}

// MARK: - Moving out of the catalog

@Test func pluginOptionsMoveToAgentsOnce() throws {
    let toml = "theme = \"mocha-neon\"\n\n[plugins.agents]\ndone_after = 0\nterminal = \"iTerm\"\nsource = \"poll\"\n\n[plugins.gh-prs]\nrepos = [\"a/b\"]\n"
    let next = try #require(agentsMigration(toml: toml))
    let c = loadConfig(toml: next)
    #expect(c.problems == [])
    #expect(c.config.agentsDoneAfter == 0 && c.config.agentsTerminal == "iTerm" && c.config.agentsTuios)
    #expect(c.config.pluginOptions["agents"] == nil && c.config.pluginOptions["gh-prs"] == ["repos": .strings(["a/b"])])
    #expect(agentsMigration(toml: next) == nil)
    let off = try #require(agentsMigration(toml: "[plugins.agents]\nenabled = false\n"))
    #expect(!loadConfig(toml: off).config.agentsTuios && !loadConfig(toml: off).config.disabledPlugins.contains("agents"))
    #expect(agentsMigration(toml: "theme = \"mocha-neon\"\n") == nil)
}

@Test func agentsConfigReadsAndReportsTypos() {
    let c = loadConfig(toml: "[agents]\ntuios = false\nclaude = false\ndone_after = 5\nterminal = \"Warp\"\nsorce = 1\n")
    #expect(!c.config.agentsTuios && !c.config.agentsClaude && c.config.agentsDoneAfter == 5 && c.config.agentsTerminal == "Warp")
    #expect(c.problems == ["agents.sorce: unknown key, ignored"])
    #expect(GzymsConfig.defaults.agentsTuios && GzymsConfig.defaults.agentsClaude && GzymsConfig.defaults.agentsDoneAfter == 3)
}

@Test func onlyAnUntouchedCatalogCopyCountsAsOurs() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-agm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try installCatalogPlugin(in: dir, CatalogPlugin(name: "agents", summary: "", manifest: "command = \"./plugin.sh\"\n", script: "echo old\n"))
    #expect(isUntouchedCatalogCopy(in: dir, folder: "agents"))
    try "echo mine\n".write(to: dir.appending(path: "agents/plugin.sh"), atomically: true, encoding: .utf8)
    #expect(!isUntouchedCatalogCopy(in: dir, folder: "agents"))
    #expect(!isUntouchedCatalogCopy(in: dir, folder: "none"))
}
