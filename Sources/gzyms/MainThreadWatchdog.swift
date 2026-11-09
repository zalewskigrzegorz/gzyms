import Foundation
import GzymsCore

/// Pings the main thread from a background queue every 0.1 s. Every freeze a user feels is main blocked.
final class MainThreadWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "gzyms.watchdog")
    private var tracker = StallTracker(threshold: 0.25)  // confined to `queue`
    private var timer: DispatchSourceTimer?
    private var lastLatency: TimeInterval = 0  // confined to `queue`
    /// Until when a stall is expected, and why ("start", "wake", "screens"); confined to `queue`.
    private var settlingUntil: TimeInterval = 0
    private var settlingWhy = ""
    private var isAsleep = false  // confined to `queue`
    private let anomalies: AnomalyLog

    init(anomalies: AnomalyLog) { self.anomalies = anomalies }

    /// Round trip of the last ping that came back, in ms.
    var lagMs: Double { queue.sync { lastLatency * 1000 } }

    /// The next `seconds` the Mac and Gzyms settle (launch, wake from sleep, screens changing): main is busy on
    /// purpose, so a stall then is logged as `settling_stall` with the reason. The log watcher warns on real ones only.
    func settling(_ why: String, for seconds: TimeInterval = 10) {
        let until = ProcessInfo.processInfo.systemUptime + seconds
        queue.async { [self] in settlingUntil = until; settlingWhy = why }
    }

    /// Screens off or the Mac going to sleep: macOS freezes or starves Gzyms in DarkWake, which is not a hang anyone sees.
    func asleep(_ value: Bool) { queue.async { [self] in isAsleep = value } }

    func start() {
        settling("start")
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 0.1, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let r = tracker.tick(at: now)
        if r.sendPing {
            // Lives as long as the app, so strong captures are fine. The time is taken on main, when it answers.
            DispatchQueue.main.async { [self] in
                let answered = ProcessInfo.processInfo.systemUptime
                queue.async { [self] in if let l = tracker.pong(at: answered) { lastLatency = l } }
            }
        }
        if let blocked = r.blocked {
            let kind = StallTracker.kind(blocked: blocked, asleep: isAsleep, settling: now < settlingUntil)
            var detail = ["blocked_ms": String(Int(blocked * 1000))]
            if kind == "settling_stall" { detail["after"] = settlingWhy }
            if kind == "main_thread_stall" { detail.merge(MacContext.read().detail) { own, _ in own } }
            anomalies.write(kind: kind, detail: detail)
        }
    }
}
