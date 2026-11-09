import Foundation

/// Append-only JSON lines in `~/Library/Logs/Gzyms/anomalies.jsonl`, easy to paste to an agent.
/// Rotates to `anomalies.1.jsonl` past 5 MB so it never grows without bound.
public final class AnomalyLog: @unchecked Sendable {
    static let maxBytes = 5 * 1024 * 1024
    private let file: URL
    private let rotated: URL
    private let lock = NSLock()
    private var on = true

    /// Written even with the detector off: a few lines a day, and the ones a report cannot do without
    /// (2026-11-09: five NC restarts never reached the file).
    public static let alwaysKinds: Set<String> = ["nc_stuck", "nc_restart", "nc_restart_failed", "main_thread_stall"]

    /// `[debug] anomalies = false` stops the writing except `alwaysKinds`; the watchdog keeps measuring lag for the HUD.
    public var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return on }
        set { lock.lock(); on = newValue; lock.unlock() }
    }

    public init(dir: URL) {
        file = dir.appendingPathComponent("anomalies.jsonl")
        rotated = dir.appendingPathComponent("anomalies.1.jsonl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func write(kind: String, detail: [String: String]) {
        let entry: [String: Any] = ["ts": Date().ISO8601Format(), "kind": kind, "detail": detail]
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        guard on || Self.alwaysKinds.contains(kind) else { return }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > Self.maxBytes {
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: file, to: rotated)
        }
        // The throwing FileHandle API: the old write(_:) raises an uncatchable exception on a full disk.
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: line); try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }
}
