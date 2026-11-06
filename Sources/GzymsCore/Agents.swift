import Foundation

/// Coding agents on the bar (Settings → Agents), built into Gzyms. Each integration is its own source with its own
/// switch, so a broken one never takes the others down. The pill goes where the catalog plugin's went: slot
/// `plugin:agents`, notifications `plugin:agents:<agent key>`.
public let agentsPill = "agents"

public enum AgentSource: String, CaseIterable, Sendable {
    case tuios, claude
    public var title: String { self == .tuios ? "tuios" : "Claude Code" }
}

/// The order rows sort in: what needs you first.
public enum AgentState: String, CaseIterable, Sendable {
    case waits, done, working, idle
    public var color: String {
        switch self {
        case .waits: "peach"
        case .working: "sky"
        case .done: "green"
        case .idle: "overlay"
        }
    }
}

public struct Agent: Equatable, Sendable {
    public var source: AgentSource
    public var id: String
    public var name: String
    /// On the right of its row: the tuios session, or the folder Claude runs in.
    public var place: String
    public var state: AgentState
    public var message: String
    /// When this state began, if the source says (Claude does). nil = when Gzyms saw it.
    public var since: Date?
    /// Where a click goes: the tuios session, or the app a Claude session runs in (nil = unknown).
    public var target: String?
    public init(source: AgentSource, id: String, name: String, place: String, state: AgentState, message: String = "",
                since: Date? = nil, target: String? = nil) {
        self.source = source; self.id = id; self.name = name; self.place = place; self.state = state; self.message = message
        self.since = since; self.target = target
    }
    /// Its row's id and its notification's: unique across sources.
    public var key: String { "\(source.rawValue):\(id)" }
}

public struct AgentsError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - tuios

/// `tuios` on PATH, else where Homebrew puts it. nil = not installed.
public func tuiosBinary(path: String?, exists: (String) -> Bool) -> String? {
    ((path ?? "").split(separator: ":").map { "\($0)/tuios" } + ["/opt/homebrew/bin/tuios", "/usr/local/bin/tuios"]).first(where: exists)
}

/// `tuios list-agents --all-sessions --json`. On failure tuios prints `{"error":"…","success":false}`: its own words are the message.
public func tuiosAgents(stdout: Data, stderr: Data = Data()) -> Result<[Agent], AgentsError> {
    struct Meta: Decodable { var prompt: String? }
    struct Row: Decodable {
        var window_id: String?, session: String?, state: String?, needs_you: Bool?, name: String?, message: String?
        var meta: Meta?
    }
    struct Raw: Decodable { var agents: [Row]?; var error: String? }
    for data in [stdout, stderr] {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { continue }
        if let e = raw.error, !e.isEmpty { return .failure(AgentsError(e)) }
        guard let rows = raw.agents else { continue }
        return .success(rows.compactMap { r in
            guard let id = r.window_id, !id.isEmpty else { return nil }
            let state: AgentState = r.needs_you == true ? .waits : r.state == "working" ? .working : r.state == "done" ? .done : .idle
            let message = (r.message ?? "").isEmpty ? r.meta?.prompt ?? "" : r.message ?? ""
            return Agent(source: .tuios, id: id, name: r.name ?? id, place: r.session ?? "", state: state, message: message, target: r.session)
        })
    }
    let said = String(decoding: stderr.isEmpty ? stdout : stderr, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
    return .failure(AgentsError(said.isEmpty ? "tuios gave no answer." : "tuios: \(said.prefix(200))"))
}

/// `tuios list-clients --json`: the client showing that session, else any that shows one. Gzyms is no pane, so tuios cannot pick.
public func tuiosClient(_ data: Data, session: String) -> String? {
    struct C: Decodable { var client_id: String?; var session: String? }
    let all = ((try? JSONDecoder().decode([C].self, from: data)) ?? []).filter { !($0.session ?? "").isEmpty }
    return (all.first { $0.session == session } ?? all.first)?.client_id
}

// MARK: - Claude Code

/// One `<session>.json` the Gzyms Claude Code plugin writes into `~/Library/Application Support/Gzyms/agents/claude/`.
public struct ClaudeSession: Equatable, Sendable {
    public var id: String
    public var state: AgentState
    public var since: Date
    /// The claude process; 0 = unknown.
    public var pid: Int32
    public var transcript: String
    public var cwd: String
    public var name: String
    public var message: String
    /// Set when it runs in a tuios pane: then tuios shows it.
    public var tuiosPane: String
    /// TERM_PROGRAM and CLAUDE_CODE_ENTRYPOINT: which app to bring forward.
    public var term: String
    public var entry: String
}

/// nil = half written or not one of ours.
public func claudeSession(_ data: Data) -> ClaudeSession? {
    struct Raw: Decodable {
        var id: String?, state: String?, since: Double?, pid: Int32?, transcript: String?, cwd: String?, name: String?, message: String?
        var tuios_pane: String?, term: String?, entry: String?
    }
    guard let r = try? JSONDecoder().decode(Raw.self, from: data), let id = r.id, !id.isEmpty,
          let state = r.state.flatMap(AgentState.init(rawValue:)), let since = r.since else { return nil }
    let cwd = r.cwd ?? ""
    return ClaudeSession(id: id, state: state, since: Date(timeIntervalSince1970: since), pid: r.pid ?? 0, transcript: r.transcript ?? "",
                         cwd: cwd, name: (r.name ?? "").isEmpty ? (cwd as NSString).lastPathComponent : r.name ?? "", message: r.message ?? "",
                         tuiosPane: r.tuios_pane ?? "", term: r.term ?? "", entry: r.entry ?? "")
}

/// The app a Claude session runs in, for `open -a`. nil = no match (the click does nothing and says so in the log).
public func claudeApp(term: String, entry: String) -> String? {
    if entry.localizedCaseInsensitiveContains("desktop") { return "Claude" }
    return ["ghostty": "Ghostty", "iTerm.app": "iTerm", "Apple_Terminal": "Terminal", "vscode": "Visual Studio Code", "WarpTerminal": "Warp"][term]
}

/// The sessions that show, and the files of dead ones to delete. No hook fires when Claude dies with its window, and none
/// when you reject a prompt or press Esc: a gone process drops the session, a transcript written after "waits" means idle.
/// With tuios on, a session in a tuios pane is left to tuios, so no agent shows twice.
public func claudeAgents(_ sessions: [ClaudeSession], tuiosOn: Bool, alive: (Int32) -> Bool, modified: (String) -> Date?) -> (agents: [Agent], dead: [String]) {
    var agents: [Agent] = [], dead: [String] = []
    for s in sessions {
        if s.pid > 0, !alive(s.pid) { dead.append(s.id); continue }
        if tuiosOn, !s.tuiosPane.isEmpty { continue }
        var state = s.state
        if state == .waits, let m = modified(s.transcript), m.timeIntervalSince(s.since) > 2 { state = .idle }
        agents.append(Agent(source: .claude, id: s.id, name: s.name, place: (s.cwd as NSString).lastPathComponent, state: state,
                            message: s.message, since: s.since, target: claudeApp(term: s.term, entry: s.entry)))
    }
    return (agents, dead)
}

// MARK: - The pill

/// What one source last said: its agents (the last good ones when it fails) and what broke.
public struct AgentSourceLook: Equatable, Sendable {
    public var agents: [Agent]
    public var problem: String?
    public var since: Date?
    public init(agents: [Agent] = [], problem: String? = nil, since: Date? = nil) { self.agents = agents; self.problem = problem; self.since = since }
}

/// Waits first, then done, working, idle; by name within a state.
public func sortedAgents(_ a: [Agent]) -> [Agent] {
    let rank = Dictionary(uniqueKeysWithValues: AgentState.allCases.enumerated().map { ($1, $0) })
    return a.sorted { (rank[$0.state]!, $0.name, $0.key) < (rank[$1.state]!, $1.name, $1.key) }
}

/// The pill for the sources that are on. A failing source greys out only its own rows, under its message.
/// Every source failing greys the whole pill.
public func agentsItem(_ looks: [AgentSource: AgentSourceLook]) -> (item: PluginItem, failure: PluginFailure?) {
    let failed = looks.filter { $0.value.problem != nil }
    let allFailed = !looks.isEmpty && failed.count == looks.count
    var rows: [PluginRow] = allFailed ? [] : AgentSource.allCases.compactMap { s in
        failed[s].map { PluginRow(text: ":exclamationmark.triangle.fill@peach: \(s.title): \($0.problem ?? "")") }
    }
    let all = sortedAgents(looks.values.flatMap(\.agents))
    rows += all.map { a in
        let text = a.state == .waits && !a.message.isEmpty ? "\(a.name) · \(a.message)" : a.name
        return PluginRow(id: a.key, text: text, tag: a.state.rawValue, color: a.state.color, detail: a.place,
                         dim: a.state == .idle || failed[a.source] != nil)
    }
    if all.isEmpty && rows.isEmpty { rows = [PluginRow(text: "No agents.")] }
    let live = all.filter { failed[$0.source] == nil }
    let waiting = live.filter { $0.state == .waits }.count, working = live.filter { $0.state == .working }.count
    let (text, color) = waiting > 0 ? ("\(waiting)", "peach") : working > 0 ? ("\(working)", "sky") : ("", "overlay")
    let failure = allFailed ? PluginFailure(message: AgentSource.allCases.compactMap { failed[$0]?.problem }.joined(separator: " "),
                                            since: failed.values.compactMap(\.since).min() ?? Date()) : nil
    return (PluginItem(id: agentsPill, text: text, icon: "sparkles", color: color, tooltip: "\(waiting) waiting, \(working) working", menu: rows), failure)
}

/// One source on Settings → Agents: its state in a few words, and in full what broke.
public struct AgentSourceStatus: Equatable, Sendable {
    public var line: String
    public var problem: String?
    public var notInstalled: Bool
    public init(line: String, problem: String? = nil, notInstalled: Bool = false) { self.line = line; self.problem = problem; self.notInstalled = notInstalled }
}

public func agentSourceStatus(on: Bool, look: AgentSourceLook?, notInstalled: Bool) -> AgentSourceStatus {
    guard on else { return AgentSourceStatus(line: "Off") }
    if notInstalled { return AgentSourceStatus(line: "Plugin not installed", notInstalled: true) }
    guard let look else { return AgentSourceStatus(line: "Starting") }
    if let p = look.problem {
        let first = p.components(separatedBy: ". ").first ?? p
        return AgentSourceStatus(line: first.hasSuffix(".") ? String(first.dropLast()) : first, problem: p)
    }
    let n = look.agents.count
    return AgentSourceStatus(line: n == 0 ? "No agents" : n == 1 ? "1 agent" : "\(n) agents")
}

// MARK: - When to notify

/// Decides the banners: once when an agent starts to wait, once when a run of at least `doneAfter` ends.
/// An agent has at most one notification, and it goes when the agent leaves that state or the bar.
/// The first look of a source (after Gzyms starts or the source comes on) only looks.
public struct AgentWatch: Sendable {
    private struct Seen: Sendable { var state: AgentState; var workingSince: Date?; var note: AgentState? }
    private var seen: [String: Seen] = [:]
    private var looked: Set<AgentSource> = []
    public init() {}

    public static func noteID(_ key: String) -> String { "plugin:\(agentsPill):\(key)" }
    /// The agent a notification is about; nil = not an agent's.
    public static func key(noteID id: String) -> String? {
        let prefix = noteID("")
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : nil
    }

    /// Notifications to take away (first) and to post.
    public mutating func look(_ source: AgentSource, _ agents: [Agent], now: Date, doneAfter: TimeInterval) -> (dismiss: [String], notify: [GzymsNotification]) {
        let first = looked.insert(source).inserted
        var dismiss: [String] = [], notify: [GzymsNotification] = []
        let keys = Set(agents.map(\.key))
        for (k, s) in seen where k.hasPrefix(source.rawValue + ":") && !keys.contains(k) {
            if s.note != nil { dismiss.append(Self.noteID(k)) }
            seen[k] = nil
        }
        for a in agents {
            let old = seen[a.key]
            var s = Seen(state: a.state, workingSince: a.state == .working ? (old?.state == .working ? old?.workingSince : a.since ?? now) : nil,
                         note: old?.note)
            // You answered, or it works again: the notification has nothing left to say.
            if let n = s.note, n == .waits ? a.state != .waits : (a.state == .working || a.state == .waits) {
                dismiss.append(Self.noteID(a.key))
                s.note = nil
            }
            if !first, a.state == .waits, old?.state != .waits {
                notify.append(note(a, level: .warning, sound: "waiting", title: "\(a.name) waits for you", body: a.message, now: now))
                s.note = .waits
            } else if !first, old?.state == .working, a.state == .done || a.state == .idle, let start = old?.workingSince {
                let took = (a.since ?? now).timeIntervalSince(start)
                if took >= doneAfter {
                    notify.append(note(a, level: .info, sound: "success", title: "\(a.name) is done", body: "after \(Int((took / 60).rounded(.up))) min", now: now))
                    s.note = .done
                }
            }
            seen[a.key] = s
        }
        return (dismiss, notify)
    }

    /// The source went off: its agents leave, and so do their notifications. Its next first look is quiet again.
    public mutating func forget(_ source: AgentSource) -> [String] {
        defer { looked.remove(source) }
        return look(source, [], now: Date(), doneAfter: 0).dismiss
    }

    private func note(_ a: Agent, level: NotifyLevel, sound: String, title: String, body: String, now: Date) -> GzymsNotification {
        GzymsNotification(id: Self.noteID(a.key), app: nil, level: level, title: title, subtitle: "\(a.place) · click to go there",
                          body: body.isEmpty ? nil : body, link: nil, altLink: nil, sound: sound, at: now)
    }
}

// MARK: - Moving out of the catalog

/// The catalog `agents` plugin moved into Gzyms: its `[plugins.agents]` options go to `[agents]` once (they are taken
/// out of `[plugins.agents]`, so it never runs twice). nil = nothing to move.
public func agentsMigration(toml: String) -> String? {
    let load = loadConfig(toml: toml)
    guard !load.broken else { return nil }
    let options = load.config.pluginOptions[agentsPill] ?? [:], off = load.config.disabledPlugins.contains(agentsPill)
    guard !options.isEmpty || off else { return nil }
    var out = toml
    for key in ["done_after", "terminal"] { if let v = options[key] { out = setting(key, to: v, in: .table(["agents"]), toml: out) } }
    if off { out = setting("tuios", to: .bool(false), in: .table(["agents"]), toml: out) }
    for key in Array(options.keys) + ["enabled"] { out = setting(key, to: nil, in: .table(["plugins", agentsPill]), toml: out) }
    return out
}

/// The folder holds exactly the files Gzyms last wrote there (its `.gzyms-catalog` matches): nobody edited it.
public func isUntouchedCatalogCopy(in dir: URL, folder: String) -> Bool {
    let f = dir.appendingPathComponent(folder)
    let read = { (n: String) in try? String(contentsOf: f.appendingPathComponent(n), encoding: .utf8) }
    guard let manifest = read("plugin.toml"), let script = read("plugin.sh"), let marker = read(catalogMarker) else { return false }
    return marker.trimmingCharacters(in: .whitespacesAndNewlines) == catalogHash(manifest: manifest, script: script)
}
