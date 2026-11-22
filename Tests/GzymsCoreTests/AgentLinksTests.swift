import Foundation
import Testing
@testable import GzymsCore

private let b = RepoBranch(ref: "o/r@b")!
private func agent(_ id: String, _ state: AgentState, _ branch: RepoBranch?, name: String? = nil) -> Agent {
    Agent(source: .tuios, id: id, name: name ?? id, place: "s", state: state, branch: branch)
}
private func pill(_ plugin: String, _ rows: [PluginRow]) -> PluginPill { PluginPill(plugin: plugin, item: PluginItem(id: plugin, text: "", menu: rows)) }
private func agentsPillOf(_ agents: [Agent]) -> PluginPill { pill(agentsPill, agents.map { PluginRow(id: $0.key, text: $0.name) }) }

@Test func gitBranchNeedsBoth() {
    #expect(gitBranch(remote: "git@github.com:O/R.git\n", head: "feat/x\n") == RepoBranch(repo: "o/r", branch: "feat/x"))
    #expect(gitBranch(remote: "git@github.com:o/r.git", head: "\n") == nil)  // detached HEAD
    #expect(gitBranch(remote: "https://gitlab.com/o/r", head: "main") == nil)
}

@Test func resolveBranchAsksGitInTheFolder() {
    var asked: [[String]] = []
    let run: CommandRunner = { _, args in
        asked.append(args)
        return args.contains("remote") ? CommandOutput(0, out: "https://github.com/o/r.git\n") : CommandOutput(0, out: "b\n")
    }
    #expect(resolveBranch(cwd: "/w", run: run) == b)
    #expect(asked.allSatisfy { $0.starts(with: ["-C", "/w"]) })
    // git failed or timed out (the runner gives a non-zero status): no branch
    #expect(resolveBranch(cwd: "/w", run: { _, _ in CommandOutput(-1, err: "killed") }) == nil)
}

@Test func agentsKeepTheirFolder() throws {
    let json = #"{"agents":[{"window_id":"w1","session":"s","state":"working","name":"n","cwd":"/code/r"}]}"#
    #expect(try tuiosAgents(stdout: Data(json.utf8)).get().first?.cwd == "/code/r")
    let s = ClaudeSession(id: "c", state: .working, since: Date(), pid: 0, transcript: "", cwd: "/code/q", name: "q", message: "",
                          tuiosPane: "", term: "", entry: "")
    #expect(claudeAgents([s], tuiosOn: false, alive: { _ in true }, modified: { _ in nil }).agents.first?.cwd == "/code/q")
}

@Test func thePillTakesTheAgentThatNeedsYou() {
    var r1 = PluginRow(id: "pr:1", text: "a"), r2 = PluginRow(id: "pr:2", text: "b")
    r1.agents = [RowAgent(key: "k1", name: "w", state: .working)]
    r2.agents = [RowAgent(key: "k2", name: "d", state: .done), RowAgent(key: "k3", name: "q", state: .waits)]
    #expect(pillAgent(PluginItem(id: "p", text: "", menu: [r1, r2])) == .waits)
    #expect(pillAgent(PluginItem(id: "p", text: "", menu: [PluginRow(id: "x", text: "c")])) == nil)
}

@Test func noteGetsTheAgentOnItsBranch() {
    var n = GzymsNotification(id: "plugin:gh-prs:ci", app: nil, level: .warning, title: "r#1 CI failed", subtitle: nil, body: nil,
                              link: "https://x", altLink: nil, sound: nil, at: Date())
    n.branch = b
    let out = withAgent(n, agents: [agent("w", .working, b), agent("q", .waits, b)])
    #expect(out.agentKey == agent("q", .waits, b).key && out.altLabel == "Open agent" && out.altLink == nil && out.link == "https://x")
}

@Test func noteWithoutAgentKeepsPluginAlt() {
    var n = GzymsNotification(id: "plugin:gh-prs:ci", app: nil, level: .info, title: "t", subtitle: nil, body: nil,
                              link: nil, altLink: "https://alt", sound: nil, at: Date())
    n.altLabel = "Logs"; n.branch = b
    #expect(withAgent(n, agents: [agent("x", .working, RepoBranch(ref: "o/r@other"))]) == n)
    n.branch = nil
    #expect(withAgent(n, agents: [agent("q", .waits, b)]) == n)
}

@Test func refParses() {
    #expect(RepoBranch(ref: "O/R@feat/x") == RepoBranch(repo: "o/r", branch: "feat/x"))
    #expect(RepoBranch(ref: "O/R@feat/x")?.ref == "o/r@feat/x")
    for bad in ["o/r", "@b", "o/r@", "r@b", ""] { #expect(RepoBranch(ref: bad) == nil, "\(bad)") }
}

@Test func remoteSlugParsesOnlyGitHub() {
    for u in ["https://github.com/O/r", "https://github.com/o/r.git", "git@github.com:o/r.git", "git@github.com:o/r", "ssh://git@github.com/o/r.git"] {
        #expect(remoteSlug(u) == "o/r", "\(u)")
    }
    for u in ["https://gitlab.com/o/r", "/tmp/repo", "", "https://github.com/o"] { #expect(remoteSlug(u) == nil, "\(u)") }
}

@Test func twoAgentsOnOneBranch() {
    let w = agent("w", .working, b), q = agent("q", .waits, b)
    let out = linkAgents([pill("gh-prs", [PluginRow(id: "pr:o/r#1", text: "r#1", branch: b)])], agents: [w, q])
    let row = out[0].item.menu![0]
    #expect(row.agents.map(\.name) == ["q", "w"])
    #expect(row.alt == .agent(q.key))
}

@Test func agentLinksToOneRow() {
    let a = agent("a", .working, b)
    let pills = [pill("gh-builds", [PluginRow(id: "t:o/r#1", text: "r#1", detail: "built", branch: b)]),
                 pill("gh-prs", [PluginRow(id: "pr:o/r#1", text: "r#1", detail: ":checkmark.circle@green: passed", branch: b)]),
                 agentsPillOf([a])]
    let row = linkAgents(pills, agents: [a]).first { $0.plugin == agentsPill }!.item.menu![0]
    #expect(row.alt == .row(plugin: "gh-prs", id: "pr:o/r#1"))
    #expect(row.gitLine == "b  :checkmark.circle@green: passed")
}

@Test func agentWithoutPRShowsBranchOnly() {
    let a = agent("a", .working, b)
    let row = linkAgents([agentsPillOf([a])], agents: [a])[0].item.menu![0]
    #expect(row.gitLine == "b" && row.alt == nil)
}

@Test func agentWithoutBranchGetsNothing() {
    let a = agent("a", .working, nil)
    let pills = [pill("gh-prs", [PluginRow(id: "pr:o/r#1", text: "r#1", branch: b)]), agentsPillOf([a])]
    let out = linkAgents(pills, agents: [a])
    #expect(out[0].item.menu![0].agents.isEmpty && out[0].item.menu![0].alt == nil)
    #expect(out[1].item.menu![0].gitLine == nil && out[1].item.menu![0].alt == nil)
}
