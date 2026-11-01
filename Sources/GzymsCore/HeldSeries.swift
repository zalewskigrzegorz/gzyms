import Darwin
import Foundation

/// Values from the last `window` seconds, for the HUD's charts and its "max over 60 s".
public struct HeldSeries: Sendable {
    public let window: TimeInterval
    private var items: [(at: TimeInterval, value: Double)] = []

    public init(window: TimeInterval = 60) { self.window = window }

    public mutating func add(_ value: Double, at now: TimeInterval) {
        items.append((now, value))
        items.removeAll { now - $0.at > window }
    }

    public var values: [Double] { items.map(\.value) }
    public var max: Double { items.map(\.value).max() ?? 0 }
}

/// The HUD's "hide for a moment": back after `duration`, or at once on `gzyms hud`.
public struct HUDHide: Sendable {
    public enum Command: Sendable { case show, quit }
    public static let duration: TimeInterval = 30
    private var until: TimeInterval?

    public init() {}

    public var isHidden: Bool { until != nil }

    public mutating func hide(at now: TimeInterval) { until = now + Self.duration }

    /// True once, when the hidden HUD should come back.
    public mutating func dueToShow(at now: TimeInterval) -> Bool {
        guard let u = until, now >= u else { return false }
        until = nil
        return true
    }

    /// `gzyms hud` while hidden brings the HUD back; while shown it closes it, as before.
    public mutating func command() -> Command {
        guard isHidden else { return .quit }
        until = nil
        return .show
    }
}

/// CPU time and memory of another process, read with `proc_pid_rusage` (no subprocess).
public enum ProcessUsage {
    public static func sample(pid: Int32) -> (cpuSeconds: Double, residentMB: Double)? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard rc == 0 else { return nil }
        // ri_*_time is in mach absolute time units; convert to seconds.
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        let cpu = ticks * Double(tb.numer) / Double(tb.denom) / 1e9
        return (cpu, Double(info.ri_phys_footprint) / 1_048_576)
    }

    public static func cpuPercent(prev: Double, now: Double, wall: TimeInterval) -> Double {
        wall > 0 ? (now - prev) / wall * 100 : 0
    }
}
