import Foundation
import GzymsCore

/// Coding agents on the bar (`Agents.swift` decides, this only fetches and clicks). tuios: `tuios subscribe` says
/// when to look again, plus a look every 60 s for a closed pane or a new name. Claude Code: the folder the Gzyms
/// Claude plugin writes, watched, plus a look every 5 s (a dead process or a transcript moving sends no event).
@MainActor
final class AgentsHost {
    struct Settings: Equatable { var tuios = false, claude = false, doneAfter = 3, terminal = "Ghostty" }

    static let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Gzyms/agents/claude")

    private var settings = Settings()
    private var looks: [AgentSource: AgentSourceLook] = [:]
    private var watch = AgentWatch()
    private var subscribe: Process?
    private var timers: [AgentSource: Timer] = [:]
    private var tuiosBusy = false, tuiosAgain = false
    private var dirWatch: DispatchSourceFileSystemObject?
    private var plugin = ClaudePluginLook()
    private var shown: (item: PluginItem, failure: PluginFailure?)?
    /// nil = no source on, no pill.
    var onPill: (PluginPill?) -> Void = { _ in }
    var onNotify: (GzymsNotification) -> Void = { _ in }
    var onDismiss: (String) -> Void = { _ in }
    var onStatus: ([AgentSource: AgentSourceStatus]) -> Void = { _ in }

    func apply(_ s: Settings) {
        let old = settings
        settings = s
        if s.tuios != old.tuios { s.tuios ? startTuios() : stop(.tuios) }
        if s.claude != old.claude { s.claude ? startClaude() : stop(.claude) }
        // tuios on or off decides which Claude sessions are tuios's.
        if s.claude, s.tuios != old.tuios { lookClaude() }
        publish()
    }

    func stopAll() { apply(Settings()) }

    // MARK: - tuios

    private var tuiosPath: String? {
        tuiosBinary(path: ProcessInfo.processInfo.environment["PATH"]) { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func startTuios() {
        subscribeTuios()
        every(60, .tuios) { $0.lookTuios() }
        lookTuios()
    }

    /// Each line means "look again". A tuios restart ends the stream, so it starts again after 2 s.
    private func subscribeTuios() {
        guard settings.tuios, subscribe == nil, let bin = tuiosPath else { return }
        let p = Process(), out = Pipe()
        p.executableURL = URL(filePath: bin)
        p.arguments = ["subscribe", "--types", "agent-state"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard !h.availableData.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.lookTuios() } }
        }
        p.terminationHandler = { [weak self] p in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated {
                    guard let self, self.subscribe === p else { return }
                    self.subscribe = nil
                    self.subscribeTuios()
                }
            }
        }
        do { try p.run(); subscribe = p } catch { log("agents: tuios subscribe did not start: \(error.localizedDescription)") }
    }

    private func lookTuios() {
        guard settings.tuios else { return }
        guard !tuiosBusy else { tuiosAgain = true; return }
        guard let bin = tuiosPath else {
            failed(.tuios, "tuios is not installed. Install it, or turn tuios off in Settings → Agents.")
            return
        }
        subscribeTuios()  // installed since the last look
        tuiosBusy = true
        Self.run(bin, ["list-agents", "--all-sessions", "--json"]) { [weak self] out, err in
            guard let self else { return }
            tuiosBusy = false
            guard settings.tuios else { return }
            switch tuiosAgents(stdout: out, stderr: err) {
            case .success(let agents): looked(.tuios, agents)
            case .failure(let e): failed(.tuios, e.message)
            }
            if tuiosAgain { tuiosAgain = false; lookTuios() }
        }
    }

    // MARK: - Claude Code

    private func startClaude() {
        every(5, .claude) { $0.lookClaude() }
        lookClaude()
        claudePlugin(nil)
    }

    /// Settings → Agents → Claude Code: nil checks the Gzyms plugin, else installs or removes it. One run at a time.
    func claudePlugin(_ action: ClaudePluginAction?) {
        guard plugin.step == nil else { return }
        if let action { plugin = ClaudePluginLook(state: plugin.state, step: action == .install ? "Installing" : "Removing"); publish() }
        DispatchQueue.global().async {
            let run: CommandRunner = { Self.runSync($0, $1, timeout: 120) }
            let claude = claudeBinary(home: NSHomeDirectory(), run: run, executable: FileManager.default.isExecutableFile)
            let error = action.flatMap { a in
                changeClaudePlugin(a, claude: claude, run: run) { line in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.plugin.step = line; self.publish() } }
                }
            }
            let state = claudePluginState(claude: claude, run: run)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard action != nil || self.plugin.step == nil else { return }  // an install or remove runs: its own check comes
                    if let error { log("agents: claude plugin \(action?.rawValue ?? "") failed: \(error.message)") }
                    else if let action { log("agents: claude plugin \(action.rawValue) done") }
                    var problem = error?.message
                    switch state {
                    case .success(.noClaude): problem = problem ?? claudeMissing
                    case .failure(let e): problem = problem ?? e.message
                    default: break
                    }
                    self.plugin = ClaudePluginLook(state: (try? state.get()) ?? self.plugin.state, problem: problem,
                                                   note: action == .install && error == nil ? claudePluginReloadNote : nil)
                    self.publish()
                }
            }
        }
    }

    private func lookClaude() {
        guard settings.claude else { return }
        let fm = FileManager.default, dir = Self.claudeDir
        guard fm.fileExists(atPath: dir.path) else { looked(.claude, []); return }
        if dirWatch == nil { watchDir(dir) }
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" } ?? []
        let sessions = files.compactMap { (try? Data(contentsOf: $0)).flatMap(claudeSession) }
        // tuios shows its panes only while it answers. Failing, its Claude sessions come from here. Not asked yet counts as fine.
        let tuiosShows = settings.tuios && looks[.tuios].map { $0.problem == nil } ?? true
        let r = claudeAgents(sessions, tuiosOn: tuiosShows, alive: { kill($0, 0) == 0 || errno != ESRCH },
                             modified: { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date })
        for id in r.dead {
            try? fm.removeItem(at: dir.appendingPathComponent("\(id).json"))
            log("agents: claude \(id.prefix(8)) is gone, its process ended")
        }
        looked(.claude, r.agents)
    }

    /// A file written or removed is a rename or a delete in the folder.
    private func watchDir(_ dir: URL) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if src.data.contains(.delete) { self.dirWatch?.cancel(); self.dirWatch = nil }  // the folder itself went
                self.lookClaude()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirWatch = src
    }

    // MARK: - Both

    private func every(_ seconds: TimeInterval, _ s: AgentSource, _ f: @escaping @MainActor (AgentsHost) -> Void) {
        timers[s]?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in MainActor.assumeIsolated { if let self { f(self) } } }
        RunLoop.main.add(t, forMode: .common)
        timers[s] = t
    }

    private func stop(_ s: AgentSource) {
        timers.removeValue(forKey: s)?.invalidate()
        if s == .tuios { let p = subscribe; subscribe = nil; p?.terminate() }
        if s == .claude { dirWatch?.cancel(); dirWatch = nil }
        looks[s] = nil
        watch.forget(s).forEach(onDismiss)
    }

    private func looked(_ s: AgentSource, _ agents: [Agent]) {
        let r = watch.look(s, agents, now: Date(), doneAfter: TimeInterval(settings.doneAfter * 60))
        r.dismiss.forEach(onDismiss)
        r.notify.forEach(onNotify)
        if looks[s] != AgentSourceLook(agents: agents) { looks[s] = AgentSourceLook(agents: agents); publish() }
    }

    /// Its last agents stay, greyed out under the message: old, but not gone.
    private func failed(_ s: AgentSource, _ message: String) {
        let old = looks[s]
        guard old?.problem != message else { return }
        if old?.problem == nil { log("agents: \(s.rawValue) failed: \(message)") }
        looks[s] = AgentSourceLook(agents: old?.agents ?? [], problem: message, since: old?.since ?? Date())
        publish()
    }

    private func publish() {
        let on = AgentSource.allCases.filter { $0 == .tuios ? settings.tuios : settings.claude }
        onStatus(Dictionary(uniqueKeysWithValues: AgentSource.allCases.map { s in
            (s, agentSourceStatus(on: on.contains(s), look: looks[s], plugin: s == .claude ? plugin : nil))
        }))
        guard !on.isEmpty else { if shown != nil { shown = nil; onPill(nil) }; return }
        let now = agentsItem(Dictionary(uniqueKeysWithValues: on.map { ($0, looks[$0] ?? AgentSourceLook()) }))
        guard shown?.item != now.item || shown?.failure != now.failure else { return }
        shown = now
        onPill(PluginPill(plugin: agentsPill, item: now.item, failure: now.failure))
    }

    // MARK: - Clicks

    /// A row, or a notification about it: that agent's pane in tuios, or the app its Claude session runs in.
    func focus(_ key: String) {
        guard let a = looks.values.flatMap(\.agents).first(where: { $0.key == key }) else { log("agents click: \(key.prefix(16)) gone"); return }
        let short = "\(a.source.rawValue) \(a.id.prefix(8))"
        switch a.source {
        case .claude:
            guard let app = a.target else { log("agents click: \(short) runs in an app Gzyms does not know"); return }
            Self.run("/usr/bin/open", ["-a", app]) { _, _ in }
            log("agents click: \(short) brought \(app) forward")
        case .tuios:
            guard let bin = tuiosPath, let session = a.target else { return }
            let terminal = settings.terminal
            Self.run(bin, ["list-clients", "--json"]) { out, _ in
                guard let client = tuiosClient(out, session: session) else {
                    log("agents click: \(short) failed: no tuios client shows a session")
                    Self.run("/usr/bin/open", ["-a", terminal]) { _, _ in }
                    return
                }
                Self.run(bin, ["switch-session", "--client", client, session]) { _, err1 in
                    Self.run(bin, ["focus-window", "-s", session, a.id]) { _, err2 in
                        Self.run("/usr/bin/open", ["-a", terminal]) { _, _ in }
                        let why = [err1, err2].map { String(decoding: $0, as: UTF8.self).split(separator: "\n").first ?? "" }.first { !$0.isEmpty }
                        log("agents click: \(short) " + (why.map { "failed: \($0)" } ?? "focused"))
                    }
                }
            }
        }
    }

    /// Runs off the main thread, at most 10 s, and hands stdout and stderr back on it.
    private static func run(_ path: String, _ args: [String], done: @escaping @MainActor (Data, Data) -> Void) {
        DispatchQueue.global().async {
            let r = runSync(path, args, timeout: 10)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(Data(r.out.utf8), Data(r.err.utf8)) } }
        }
    }

    /// Runs and waits, at most `timeout` seconds. Never on the main thread. The CLI uses it too.
    nonisolated static func runSync(_ path: String, _ args: [String], timeout: TimeInterval) -> CommandOutput {
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(filePath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice  // nothing may wait for an answer
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let kill = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
            // Read before waiting: a full pipe would block the child forever.
            let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            kill.cancel()
            return CommandOutput(p.terminationStatus, out: String(decoding: o, as: UTF8.self), err: String(decoding: e, as: UTF8.self))
        } catch { return CommandOutput(-1, err: "\(path) did not start: \(error.localizedDescription)") }
    }
}
