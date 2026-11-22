import Foundation

/// A branch of a GitHub repo, as plugins name it: `"owner/repo@branch"`. The repo is lowercased (GitHub ignores its case),
/// the branch is kept as written.
public struct RepoBranch: Hashable, Codable, Sendable {
    public var repo: String
    public var branch: String
    public init(repo: String, branch: String) { self.repo = repo.lowercased(); self.branch = branch }
    /// nil unless it is owner/repo, an @, and a branch, none of them empty.
    public init?(ref: String) {
        guard let at = ref.firstIndex(of: "@") else { return nil }
        let repo = ref[..<at], branch = String(ref[ref.index(after: at)...])
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), !branch.isEmpty else { return nil }
        self.init(repo: String(repo), branch: branch)
    }
    public var ref: String { "\(repo)@\(branch)" }
}

/// owner/repo of a GitHub remote URL (https or ssh, with or without .git); nil for any other host or shape.
public func remoteSlug(_ url: String) -> String? {
    let s = url.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["https://github.com/", "http://github.com/", "ssh://git@github.com/", "git@github.com:"] where s.hasPrefix(prefix) {
        var rest = String(s.dropFirst(prefix.count))
        if rest.hasSuffix("/") { rest.removeLast() }
        if rest.hasSuffix(".git") { rest.removeLast(4) }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty } ? rest.lowercased() : nil
    }
    return nil
}

/// The branch a folder is on, from git's answers: the origin URL and `branch --show-current` (empty when detached).
public func gitBranch(remote: String, head: String) -> RepoBranch? {
    let h = head.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !h.isEmpty, let slug = remoteSlug(remote) else { return nil }
    return RepoBranch(repo: slug, branch: h)
}

/// Asks git in `cwd`. The runner owns the timeout; a non-zero status from either call is no branch.
public func resolveBranch(cwd: String, git: String = "/usr/bin/git", run: CommandRunner) -> RepoBranch? {
    let remote = run(git, ["-C", cwd, "remote", "get-url", "origin"])
    guard remote.status == 0 else { return nil }
    let head = run(git, ["-C", cwd, "branch", "--show-current"])
    guard head.status == 0 else { return nil }
    return gitBranch(remote: remote.out, head: head.out)
}

/// What `a` does on a row Gzyms linked: open an agent, or click a row of another plugin (the PR an agent works on).
public enum RowAlt: Equatable, Sendable {
    case agent(String)
    case row(plugin: String, id: String)
}

/// An agent as a PR row shows it: a dot in its state's colour and its name.
public struct RowAgent: Equatable, Sendable {
    public var key: String
    public var name: String
    public var state: AgentState
    public init(key: String, name: String, state: AgentState) { self.key = key; self.name = name; self.state = state }
}

/// Needs you first: waits, then working, done, idle.
private let needsYou: [AgentState] = [.waits, .working, .done, .idle]

/// Ties agents to plugin rows by repo and branch. A row with a `branch` gets the agents on it (needs-you first) and
/// `a` opens the first. A row of the agents pill gets its agent's branch as a line, with the detail of the row on that
/// branch (a PR row, `pr:`, wins over others, then plugins by name), and `a` clicks that row.
public func linkAgents(_ pills: [PluginPill], agents: [Agent]) -> [PluginPill] {
    let ordered = agents.sorted { (needsYou.firstIndex(of: $0.state)!, $0.name, $0.key) < (needsYou.firstIndex(of: $1.state)!, $1.name, $1.key) }
    let onBranch = Dictionary(grouping: ordered.filter { $0.branch != nil }) { $0.branch! }
    var target: [RepoBranch: (plugin: String, row: PluginRow)] = [:]
    for p in pills.sorted(by: { $0.plugin < $1.plugin }) where p.plugin != agentsPill {
        for r in p.item.menu ?? [] {
            guard let br = r.branch, let id = r.id else { continue }
            if target[br] == nil || (id.hasPrefix("pr:") && target[br]?.row.id?.hasPrefix("pr:") != true) { target[br] = (p.plugin, r) }
        }
    }
    let byKey = Dictionary(agents.map { ($0.key, $0) }) { a, _ in a }
    return pills.map { pill in
        var pill = pill
        pill.item.menu = pill.item.menu?.map { r in
            var r = r
            if pill.plugin == agentsPill {
                guard let id = r.id, let br = byKey[id]?.branch else { return r }
                let t = target[br]
                r.gitLine = br.branch + (t?.row.detail.map { "  " + $0 } ?? "")
                r.alt = t.map { .row(plugin: $0.plugin, id: $0.row.id!) }
            } else if let br = r.branch, let on = onBranch[br], let first = on.first {
                r.agents = on.map { RowAgent(key: $0.key, name: $0.name, state: $0.state) }
                r.alt = .agent(first.key)
            }
            return r
        }
        return pill
    }
}
