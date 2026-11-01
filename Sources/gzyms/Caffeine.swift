import Foundation
import GzymsCore

/// Keeps the Mac awake through macOS's own `caffeinate`, started in its own session: a Gzyms restart (every install)
/// or crash does not take it down (Greg: it must work on its own). Its pid and end are in caffeine.json, so a
/// fresh Gzyms picks it up again: gold pill, countdown, the "may sleep again" note at the end.
@MainActor
final class CaffeineController {
    static var file: URL { VitalsWriter.url.deletingLastPathComponent().appendingPathComponent("caffeine.json") }

    private(set) var state: CaffeineState?
    private var record: CaffeineState.Record?
    private var timer: Timer?
    var onChange: (CaffeineState?) -> Void = { _ in }
    /// After a timed run ends on its own, or the battery cut it short.
    var onEnded: (String) -> Void = { _ in }

    /// A caffeinate left running by an earlier Gzyms, if it still holds.
    func restore() {
        guard let data = try? Data(contentsOf: Self.file), let r = try? JSONDecoder().decode(CaffeineState.Record.self, from: data) else { return }
        // shortcut: "alive" is the pid answering, not proven to be caffeinate; a reused pid within the run's time is
        // the only miss, and stopping then only signals that stranger once. Check the name if it ever matters.
        guard r.live(now: Date(), alive: kill(r.pid, 0) == 0) else { try? FileManager.default.removeItem(at: Self.file); return }
        adopt(r)
        log("caffeine: still on from before the restart (pid \(r.pid))")
    }

    /// `minutes` nil = until turned off. A new start replaces a running one.
    func start(minutes: Int?, display: Bool) {
        end()
        let args = CaffeineState.command(seconds: minutes.map { $0 * 60 }, display: display)
        guard let pid = spawnDetached(args) else { log("caffeine: could not start caffeinate"); return }
        let r = CaffeineState.Record(pid: pid, until: minutes.map { Date().timeIntervalSince1970 + Double($0) * 60 }, display: display)
        try? JSONEncoder().encode(r).write(to: Self.file, options: .atomic)
        adopt(r)
        log("caffeine: on \(minutes.map { "for \($0) min" } ?? "until turned off")\(display ? ", display too" : "") (pid \(pid))")
    }

    /// `reason` set = it ended by itself (time up, low battery): say so.
    func stop(reason: String? = nil) {
        guard state != nil else { return }
        end()
        log("caffeine: off\(reason.map { " (\($0))" } ?? "")")
        if let reason { onEnded(reason) }
    }

    private func adopt(_ r: CaffeineState.Record) {
        record = r
        state = r.state
        timer?.invalidate(); timer = nil
        if let until = r.until {
            // caffeinate -t ends by itself; this only tells the bar (and the user) when it does.
            let t = Timer(fire: Date(timeIntervalSince1970: until + 1), interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: "The Mac may sleep again.") }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        onChange(state)
    }

    private func end() {
        timer?.invalidate(); timer = nil
        if let r = record, kill(r.pid, 0) == 0 { kill(r.pid, SIGTERM) }
        record = nil
        try? FileManager.default.removeItem(at: Self.file)
        if state != nil { state = nil; onChange(nil) }
    }

    /// posix_spawn with its own session: launchd ends Gzyms' whole process group on a restart, this is not in it.
    private func spawnDetached(_ args: [String]) -> Int32? {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let argv = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        return posix_spawn(&pid, args[0], nil, &attr, argv, environ) == 0 ? pid : nil
    }
}
