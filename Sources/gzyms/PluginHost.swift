import Foundation
import GzymsCore

/// Runs the plugin folders in `~/.config/gzyms/plugins/`: one long-lived process each, JSON lines both ways
/// (`Plugins.swift`). A dead plugin comes back with backoff; a disabled or removed one is stopped at once.
/// The folder is watched, so `gzyms plugin new/remove` and Finder work without a restart.
@MainActor
final class PluginHost {
    private final class Run {
        var manifest: PluginManifest
        var process: Process?
        var stdin: FileHandle?
        var buffer = Data()
        var held: [HeldItem] = []
        /// The process is gone: every pill it left greys out until the new one talks.
        var exit: PluginFailure?
        /// Started again with old pills still held: the first line it prints replaces them.
        var restarted = false
        var failures = 0
        var started = Date()
        var retry: Timer?
        var stderrLines = 0
        var problem: String?
        init(_ m: PluginManifest) { manifest = m }
    }

    let dir: URL
    private var runs: [String: Run] = [:]
    private var broken: [String: (name: String, problem: String)] = [:]  // folders whose manifest does not read
    private var disabled: Set<String> = []
    private var catalogNewer: Set<String> = []  // catalog plugins the user edited while the catalog moved on
    private var values: [String: [String: TOMLValue]] = [:]  // config.toml's `[plugins.<folder>]` options
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var staleTimer: Timer?
    private var failing: Set<String> = []
    var onItems: ([PluginPill]) -> Void = { _ in }
    var onNotify: (GzymsNotification) -> Void = { _ in }
    var onDismiss: (String) -> Void = { _ in }
    var onStatus: ([PluginStatus]) -> Void = { _ in }

    init(dir: URL) { self.dir = dir }

    func start(disabled: Set<String>, options: [String: [String: TOMLValue]]) {
        self.disabled = disabled
        values = options
        watch()
        rescan()
        // A plugin gone silent sends nothing, so a clock asks whether a pill has outlived its promise.
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkStale() } }
        RunLoop.main.add(t, forMode: .common)
        staleTimer = t
    }

    private func checkStale() {
        if Set(pills().filter { $0.failure != nil }.map(\.key)) != failing { publish() }
    }

    /// A plugin reads its options once, from its environment: a change restarts just that plugin.
    func setOptions(_ v: [String: [String: TOMLValue]]) {
        let old = values
        values = v
        let changed = runs.keys.filter { old[$0] != v[$0] }
        guard !changed.isEmpty else { return }
        for f in changed { log("plugin \(f): options changed, restarting"); stop(f) }
        rescan()
    }

    func setDisabled(_ d: Set<String>) {
        guard d != disabled else { return }
        disabled = d
        rescan()
    }

    func stopAll() { staleTimer?.invalidate(); for f in Array(runs.keys) { stop(f) } }

    func send(plugin: String, _ e: PluginEvent, id: String) {
        guard let h = runs[plugin]?.stdin else { return }
        try? h.write(contentsOf: Data((pluginEventLine(e, id: id) + "\n").utf8))
    }

    // MARK: - Folder

    /// The plugins folder and the config folder above it (so a plugins folder made later is seen too).
    private func watch() {
        watchers.forEach { $0.cancel() }
        watchers = []
        for path in [dir.path, dir.deletingLastPathComponent().path] {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link], queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
    }

    private func changed() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.watch(); self?.rescan() } }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    private func rescan() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
        var found: [String: PluginManifest] = [:]
        broken = [:]
        // agents is built in now: a copy the user changed stays on disk and does not run, or every agent would ping twice.
        for url in folders where !isPluginBackup(url.lastPathComponent) && url.lastPathComponent != agentsPill {
            let folder = url.lastPathComponent
            let toml: String?
            if runs[folder] == nil, !disabled.contains(folder) {
                let r = pluginTomlForStart(in: dir, folder: folder)
                toml = r.toml
                synced(folder, r.sync)
            } else {
                toml = try? String(contentsOf: url.appendingPathComponent("plugin.toml"), encoding: .utf8)
            }
            guard let toml else { continue }
            switch pluginManifest(toml: toml, folder: folder) {
            case .success(let m): found[folder] = m
            case .failure(let e): broken[folder] = (folder, e.message)
            }
        }
        for (folder, run) in runs where found[folder] == nil || disabled.contains(folder) || found[folder]?.command != run.manifest.command {
            stop(folder)
            if found[folder] != nil, !disabled.contains(folder) { log("plugin \(folder): changed, restarting") }
        }
        for (folder, m) in found where runs[folder] == nil && !disabled.contains(folder) {
            let r = Run(m)
            runs[folder] = r
            launch(r)
        }
        for (folder, m) in found { runs[folder]?.manifest = m }
        publish()
    }

    private func synced(_ folder: String, _ s: Result<CatalogSync, Error>) {
        switch s {
        case .success(.updated): catalogNewer.remove(folder); log("plugin \(folder): updated from the catalog")
        case .success(.editedCatalogNewer):
            if catalogNewer.insert(folder).inserted { log("plugin \(folder): you changed it, kept as it is. The catalog has another version.") }
        case .success: catalogNewer.remove(folder)
        case .failure(let e): log("plugin \(folder): could not update from the catalog: \(e.localizedDescription)")
        }
    }

    /// Settings' "Update": the old process ends, the user's copy goes to `<folder>.bak-<date>`, the catalog version starts.
    func replaceFromCatalog(_ folder: String) {
        stop(folder)
        do {
            let bak = try replaceWithCatalog(in: dir, folder: folder, now: Date())
            catalogNewer.remove(folder)
            log("plugin \(folder): replaced from the catalog, your copy is \(bak.lastPathComponent)")
        } catch { log("plugin \(folder): could not replace from the catalog: \(error.localizedDescription)") }
        rescan()
    }

    // MARK: - Processes

    private func launch(_ r: Run) {
        let folder = r.manifest.folder
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        p.arguments = ["-c", r.manifest.command]
        p.currentDirectoryURL = dir.appendingPathComponent(folder)
        p.environment = ProcessInfo.processInfo.environment.merging(pluginEnvironment(r.manifest, values: values[folder] ?? [:])) { _, new in new }
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.stdout(folder, d) } }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.stderr(folder, d) } }
        }
        p.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended(folder, p, status: status) } }
        }
        do {
            try p.run()
            r.process = p
            r.stdin = inp.fileHandleForWriting
            r.started = Date()
            r.stderrLines = 0
            r.restarted = !r.held.isEmpty
            log("plugin \(folder): started")
        } catch {
            r.problem = "could not start: \(error.localizedDescription)"
            log("plugin \(folder): \(r.problem!)")
        }
    }

    private func stop(_ folder: String) {
        guard let r = runs.removeValue(forKey: folder) else { return }
        r.retry?.invalidate()
        let p = r.process
        r.process = nil
        try? r.stdin?.close()  // EOF: a well-behaved plugin exits by itself
        p?.terminate()
        if !r.held.isEmpty { publish() }
    }

    private func ended(_ folder: String, _ p: Process, status: Int32) {
        guard let r = runs[folder], r.process === p else { return }  // stopped on purpose
        r.process = nil
        r.stdin = nil
        r.buffer = Data()
        // A plugin that ran a while and then died starts a fresh streak.
        r.failures = Date().timeIntervalSince(r.started) > 60 ? 1 : r.failures + 1
        let wait = min(60, pow(2, Double(r.failures - 1)))
        r.problem = "exited (\(status)), starting again in \(Int(wait)) s"
        // Its pills stay, greyed out: gone would hide that it broke, and the old numbers must not pass for fresh.
        r.exit = PluginFailure(message: "The plugin stopped (exit \(status)). Starting it again in \(Int(wait)) s.", since: Date())
        if r.failures <= 3 || r.failures % 10 == 0 { log("plugin \(folder): \(r.problem!)") }
        let t = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.runs[folder], r.process == nil else { return }
                r.retry = nil
                self.launch(r)
                self.publish()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        r.retry = t
        publish()
    }

    private func stdout(_ folder: String, _ d: Data) {
        guard let r = runs[folder] else { return }
        r.buffer.append(d)
        var changed = false
        while let nl = r.buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: r.buffer[..<nl], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            r.buffer.removeSubrange(...nl)
            guard !line.isEmpty else { continue }
            let now = Date()
            if r.restarted { r.held = []; r.restarted = false; changed = true }
            switch pluginMessage(line, plugin: folder, now: now) {
            case .item(let i)?:
                if let at = r.held.firstIndex(where: { $0.item.id == i.id }) {
                    let old = r.held[at], new = hold(i, previous: old, now: now)
                    r.held[at] = new
                    // A line that repeats the pill still counts: it is how a plugin says it is alive.
                    changed = changed || old.item != i || pluginFailure(old, exit: r.exit, now: now) != pluginFailure(new, exit: nil, now: now)
                } else { r.held.append(hold(i, previous: nil, now: now)); changed = true }
            case .removeItem(let id)?:
                let before = r.held.count
                r.held.removeAll { $0.item.id == id }
                changed = changed || r.held.count != before
            case .notify(let n)?: onNotify(n)
            case .dismiss(let id)?: onDismiss(id)
            case .log(let l)?: log("plugin \(folder): \(l.prefix(200))")
            case nil: log("plugin \(folder): not a message: \(line.prefix(120))")
            }
            if r.problem != nil { r.problem = nil; r.exit = nil; r.failures = 0; changed = true }  // it talks: it works
        }
        if r.buffer.count > 1 << 20 { r.buffer = Data(); log("plugin \(folder): a line over 1 MB, dropped") }
        if changed { publish() }
    }

    private func stderr(_ folder: String, _ d: Data) {
        guard let r = runs[folder], r.stderrLines < 20 else { return }
        for line in String(decoding: d, as: UTF8.self).split(separator: "\n").prefix(20 - r.stderrLines) {
            r.stderrLines += 1
            log("plugin \(folder) stderr: \(line.prefix(200))")
        }
    }

    private func pills() -> [PluginPill] {
        let now = Date()
        return runs.keys.sorted().flatMap { f in
            runs[f]!.held.map { PluginPill(plugin: f, item: $0.item, failure: pluginFailure($0, exit: runs[f]!.exit, now: now)) }
        }
    }

    private func publish() {
        let all = pills()
        failing = Set(all.filter { $0.failure != nil }.map(\.key))
        onItems(all)
        var statuses: [PluginStatus] = runs.values.map { r in
            PluginStatus(folder: r.manifest.folder, name: r.manifest.name, description: r.manifest.description, enabled: true,
                         running: r.process != nil, problem: r.problem, options: r.manifest.options,
                         catalogNewer: catalogNewer.contains(r.manifest.folder), icon: r.manifest.icon)
        }
        statuses += broken.map { PluginStatus(folder: $0.key, name: $0.value.name, description: "", enabled: !disabled.contains($0.key),
                                         running: false, problem: $0.value.problem) }
        // Disabled ones are still listed so they can be turned back on.
        let listed = Set(statuses.map(\.folder))
        for folder in disabled where !listed.contains(folder) {
            guard let toml = try? String(contentsOf: dir.appendingPathComponent(folder).appendingPathComponent("plugin.toml"), encoding: .utf8),
                  case .success(let m) = pluginManifest(toml: toml, folder: folder) else { continue }
            statuses.append(PluginStatus(folder: folder, name: m.name, description: m.description, enabled: false, running: false, options: m.options, icon: m.icon))
        }
        onStatus(statuses.sorted { $0.folder < $1.folder })
    }
}
