import Foundation

/// The Gzyms Claude Code plugin writes the session files the Claude Code source reads. Gzyms puts it in and takes it
/// out through Claude Code's own CLI (`gzyms agents install claude`, Settings → Agents → Claude Code).
public let claudePluginID = "gzyms@gzyms"
public let claudePluginMarketplace = "zalewskigrzegorz/gzyms-claude-plugin"
public let claudePluginReloadNote = "New Claude sessions pick it up. Restart open ones or run /reload-plugins."
public let claudeMissing = "Claude Code not found. Install Claude Code first, then try again."

/// What a command said.
public struct CommandOutput: Equatable, Sendable {
    public var status: Int32
    public var out: String
    public var err: String
    public init(_ status: Int32, out: String = "", err: String = "") { self.status = status; self.out = out; self.err = err }
}

/// Runs a program with its arguments and waits for it. Passed in, so tests never touch the real Claude Code.
public typealias CommandRunner = (_ path: String, _ args: [String]) -> CommandOutput

public enum ClaudePluginAction: String, Sendable { case install, remove }

public enum ClaudePluginState: Equatable, Sendable {
    case noClaude, missing
    /// Installed, with its version, and off in Claude Code: it writes nothing.
    case off(String)
    case installed(String)

    public var line: String {
        switch self {
        case .noClaude: "Claude Code not found"
        case .missing: "Not installed"
        case .off: "Off in Claude Code"
        case .installed(let v): v.isEmpty ? "Installed" : "Installed, \(v)"
        }
    }
    public var isInstalled: Bool { if case .installed = self { true } else { false } }
}

/// The plugin as Settings → Agents shows it.
public struct ClaudePluginLook: Equatable, Sendable {
    /// nil = not checked yet.
    public var state: ClaudePluginState?
    /// The step running now; nil = nothing runs.
    public var step: String?
    /// What broke on the last run or check, in Claude's own words.
    public var problem: String?
    /// After an install: what to do with the sessions already open.
    public var note: String?
    public init(state: ClaudePluginState? = nil, step: String? = nil, problem: String? = nil, note: String? = nil) {
        self.state = state; self.step = step; self.problem = problem; self.note = note
    }
}

/// `claude` for an app, whose PATH is bare: what a login shell finds, else where Claude Code's installers put it.
/// nil = not installed.
public func claudeBinary(home: String, run: CommandRunner, executable: (String) -> Bool) -> String? {
    // zsh, not the user's shell: `command -v` is not nushell.
    let shell = run("/bin/zsh", ["-lc", "command -v claude"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
    let known = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    return ([shell] + known).first { $0.hasPrefix("/") && executable($0) }
}

/// `claude plugin list --json`. nil = not that list.
public func claudePluginState(listJSON: String) -> ClaudePluginState? {
    struct Row: Decodable { var id: String?; var version: String?; var enabled: Bool? }
    guard let rows = try? JSONDecoder().decode([Row].self, from: Data(listJSON.utf8)) else { return nil }
    let ours = rows.filter { $0.id == claudePluginID }
    // Installed in two scopes: one that is on wins.
    guard let r = ours.first(where: { $0.enabled != false }) ?? ours.first else { return .missing }
    return r.enabled == false ? .off(r.version ?? "") : .installed(r.version ?? "")
}

public func claudePluginState(claude: String?, run: CommandRunner) -> Result<ClaudePluginState, AgentsError> {
    guard let claude else { return .success(.noClaude) }
    let r = run(claude, ["plugin", "list", "--json"])
    guard r.status == 0, let state = claudePluginState(listJSON: r.out) else { return .failure(AgentsError(claudeSaid(r))) }
    return .success(state)
}

/// Installs or removes the plugin, one step at a time, `say` getting each step's line. nil = it worked.
/// Running it twice is safe: "already added" and "already installed" count as done, a missing plugin needs no removing.
/// Remove leaves the marketplace in place.
public func changeClaudePlugin(_ action: ClaudePluginAction, claude: String?, run: CommandRunner, say: (String) -> Void) -> AgentsError? {
    guard let claude else { return AgentsError(claudeMissing) }
    func step(_ line: String, _ args: [String]) -> AgentsError? {
        say(line)
        let r = run(claude, args)
        return r.status == 0 || alreadyDone(r) ? nil : AgentsError(claudeSaid(r))
    }
    func state() -> Result<ClaudePluginState, AgentsError> { claudePluginState(claude: claude, run: run) }
    switch action {
    case .install:
        if let e = step("Adding the gzyms marketplace", ["plugin", "marketplace", "add", claudePluginMarketplace]) { return e }
        if let e = step("Installing \(claudePluginID)", ["plugin", "install", claudePluginID]) { return e }
        // Installed before and turned off since: install leaves it off.
        if case .success(.off) = state() { return step("Turning it on", ["plugin", "enable", claudePluginID]) }
        return nil
    case .remove:
        if case .success(.missing) = state() { say("Not installed, nothing to remove"); return nil }
        return step("Removing \(claudePluginID)", ["plugin", "uninstall", claudePluginID])
    }
}

/// Older Claude Code exits 1 on a second install or add, newer exits 0. A plugin or marketplace from another source is
/// a real failure.
private func alreadyDone(_ r: CommandOutput) -> Bool {
    let t = (r.out + "\n" + r.err).lowercased()
    return t.contains("already") && (t.contains("installed") || t.contains("added"))
        && !t.contains("different source") && !t.contains("nothing was switched")
}

/// Claude's own line: the first of stderr, else the last of stdout.
private func claudeSaid(_ r: CommandOutput) -> String {
    let lines = { (s: String) in s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    return lines(r.err).first ?? lines(r.out).last ?? "claude exited with \(r.status)."
}
