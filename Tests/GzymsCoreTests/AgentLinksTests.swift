import Foundation
import Testing
@testable import GzymsCore

private let b = RepoBranch(ref: "o/r@b")!
private func agent(_ id: String, _ state: AgentState, _ branch: RepoBranch?, name: String? = nil) -> Agent {
    Agent(source: .tuios, id: id, name: name ?? id, place: "s", state: state, branch: branch)
}
private func pill(_ plugin: String, _ rows: [PluginRow]) -> PluginPill { PluginPill(plugin: plugin, item: PluginItem(id: plugin, text: "", menu: rows)) }
private func agentsPillOf(_ agents: [Agent]) -> PluginPill { pill(agentsPill, agents.map { PluginRow(id: $0.key, text: $0.name) }) }

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
