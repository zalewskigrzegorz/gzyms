import AppKit
import GzymsCore
import GzymsUI
import Observation
import SwiftUI

/// `gzyms hud`: a separate process, so it keeps showing data when the bar hangs.
@MainActor
enum HUD {
    static var pidFile: URL { VitalsWriter.url.deletingLastPathComponent().appendingPathComponent("hud.pid") }

    static let detachedEnv = "GZYMS_HUD_DETACHED"

    private static var lock: InstanceLock?

    /// A HUD is already up (it holds the lock): poke it and report true.
    /// SIGUSR1 lets the HUD decide: show itself if hidden, quit if shown.
    static func toggleOff() -> Bool {
        try? FileManager.default.createDirectory(at: pidFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let pid = InstanceLock.holderPid(path: pidFile.path) else { return false }
        kill(pid, SIGUSR1)
        return true
    }

    /// Started from a terminal: relaunch as a detached child and let the command return,
    /// so closing the terminal does not take the HUD with it.
    static func detachFromTerminal() -> Never {
        let child = Process()
        // argv[0] is just "gzyms" when run from PATH; the bundle knows the real binary.
        guard let me = Bundle.main.executableURL?.resolvingSymlinksInPath() else { exit(1) }
        child.executableURL = me
        child.arguments = ["hud"]
        child.environment = ProcessInfo.processInfo.environment.merging([detachedEnv: "1"]) { _, new in new }
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { FileHandle.standardError.write(Data("gzyms hud: \(error)\n".utf8)); exit(1) }
        exit(0)
    }

    /// In the detached child: own session (no controlling terminal), immune to SIGHUP, holds the lock
    /// for its whole life. Losing a race with another `gzyms hud` means quitting quietly.
    static func becomeDetached() {
        setsid()
        signal(SIGHUP, SIG_IGN)
        guard let l = InstanceLock(path: pidFile.path) else { exit(0) }
        lock = l
        // Old vitals would read as "not answering" until the bar's next write; dashes are honest.
        try? FileManager.default.removeItem(at: VitalsWriter.url)
    }
}

@Observable @MainActor
final class HUDModel {
    var stats = HUDStats(lag: nil, cpu: nil, memMB: nil, panels: nil, rebuilds: nil, eventsPerSec: nil,
                         answering: true, cpuSeries: [], lagSeries: [])
    var tab: HUDTab = .stats
    var filter: LogFilter = .all
    var logs: [LogLine] = []
    var theme = HUDModel.configTheme()

    /// The same file the bar reads; its problems are the bar's to log.
    static func configTheme() -> Theme {
        GzymsCore.loadConfig(toml: try? String(contentsOf: ThemeCommand.configFile, encoding: .utf8)).config.theme
    }
}

struct HUDRoot: View {
    @Bindable var model: HUDModel
    let onHide: () -> Void
    var body: some View {
        HUDView(stats: model.stats, tab: $model.tab, logs: model.logs, filter: $model.filter, onHide: onHide)
            .themed(model.theme)
            // isMovableByWindowBackground ignores SwiftUI content, so the drag has to come from SwiftUI.
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            .contextMenu { Button("Quit HUD") { NSApp.terminate(nil) } }
    }
}

@MainActor
final class HUDController: NSObject, NSApplicationDelegate {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var signals: [DispatchSourceSignal] = []
    private var hide = HUDHide()
    private var lag = HeldSeries(), cpu = HeldSeries(), mem = HeldSeries()
    private var lastCPU: (pid: Int32, cpu: Double, at: TimeInterval)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.isMovableByWindowBackground = true
        p.contentView = NSHostingView(rootView: HUDRoot(model: model) { [weak self] in self?.hidePanel() })
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - 312, y: screen.minY + 12))
        }
        p.orderFrontRegardless()
        panel = p

        listen(SIGTERM) { NSApp.terminate(nil) }
        listen(SIGUSR1) { [weak self] in self?.command() }
        listen(SIGHUP) { [weak self] in self?.model.theme = HUDModel.configTheme() }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.2
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: HUD.pidFile)
    }

    private func listen(_ sig: Int32, _ handler: @escaping @MainActor () -> Void) {
        Darwin.signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { MainActor.assumeIsolated { handler() } }
        s.resume()
        signals.append(s)
    }

    /// Hidden, the HUD keeps sampling, so the charts have no gap when it comes back.
    private func hidePanel() {
        hide.hide(at: ProcessInfo.processInfo.systemUptime)
        panel?.orderOut(nil)
    }

    private func command() {
        switch hide.command() {
        case .show: panel?.orderFrontRegardless()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        if hide.dueToShow(at: now) { panel?.orderFrontRegardless() }
        let vitals = (try? Data(contentsOf: VitalsWriter.url)).flatMap { try? JSONDecoder().decode(Vitals.self, from: $0) }
        var stats = model.stats
        let state = vitalsFreshness(vitals, now: Date())
        // While the bar hangs, the lag is the hang so far: it climbs, in red, on the row and the chart.
        if let l = displayLagMs(state, now: Date()) {
            lag.add(l, at: now)
            stats.lag = Metric(now: l, max: lag.max)
        }
        switch state {
        case .fresh(let v):
            stats.answering = true
            stats.panels = v.panels; stats.rebuilds = v.rebuilds; stats.eventsPerSec = v.eventsPerSec
        case .notAnswering:
            stats.answering = false
        case .missing:
            stats.answering = true
            stats.lag = nil; stats.panels = nil; stats.rebuilds = nil; stats.eventsPerSec = nil
        }
        // CPU and memory are sampled from outside, so they keep coming even when the bar hangs.
        if let pid = vitals?.pid, let u = ProcessUsage.sample(pid: pid) {
            if let last = lastCPU, last.pid == pid {
                let pct = ProcessUsage.cpuPercent(prev: last.cpu, now: u.cpuSeconds, wall: now - last.at)
                cpu.add(pct, at: now)
                stats.cpu = Metric(now: pct, max: cpu.max)
            }
            lastCPU = (pid, u.cpuSeconds, now)
            mem.add(u.residentMB, at: now)
            stats.memMB = Metric(now: u.residentMB, max: mem.max)
        } else {
            stats.cpu = nil; stats.memMB = nil
        }
        stats.cpuSeries = cpu.values
        stats.lagSeries = lag.values
        model.stats = stats
        if model.tab == .logs { model.logs = LogTail.read() }
    }
}

/// The newest lines of the anomaly log and the bar's own log, newest first.
enum LogTail {
    static func read() -> [LogLine] {
        let dir = Paths.logsDir(home: FileManager.default.homeDirectoryForCurrentUser)
        let anomalies = tail(dir.appendingPathComponent("anomalies.jsonl")).map { line in
            (ts: timestamp(json: line), line: LogLine(source: "anomalies", text: line, level: line.contains("stall") || line.contains("storm") ? "error" : nil))
        }
        let log = tail(dir.appendingPathComponent("gzyms.log")).map { line in
            (ts: String(line.prefix(20)), line: LogLine(source: "log", text: line, level: nil))
        }
        return (anomalies + log).sorted { $0.ts > $1.ts }.prefix(16).map(\.line)
    }

    /// Last 16 lines from the last 16 KB, so a huge log never costs much.
    private static func tail(_ url: URL) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > 16_384 ? end - 16_384 : 0)
        let text = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        return text.split(separator: "\n").suffix(16).map(String.init)
    }

    private static func timestamp(json line: String) -> String {
        guard let r = line.range(of: #""ts":""#), let end = line[r.upperBound...].firstIndex(of: "\"") else { return "" }
        return String(line[r.upperBound..<end])
    }
}
