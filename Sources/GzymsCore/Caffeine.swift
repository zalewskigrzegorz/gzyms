import Foundation

/// Keeping the Mac awake: until a time, or until turned off (`until == .distantFuture`).
public struct CaffeineState: Equatable, Sendable {
    public var until: Date
    public init(until: Date) { self.until = until }

    public var forever: Bool { until == .distantFuture }

    /// "1h45", "25m", "∞" on the pill; rounded up, so it never reads 0 while still on.
    public func label(now: Date) -> String {
        guard !forever else { return "∞" }
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        let m = minutes % 60
        return m == 0 ? "\(minutes / 60)h" : String(format: "%dh%02d", minutes / 60, m)
    }

    /// The slider in the popup: 15 min to 8 h in 15 min steps.
    public static let steps = Array(stride(from: 15, through: 480, by: 15))

    /// The `caffeinate` behind it, written to disk so a Gzyms restart finds it again.
    public struct Record: Codable, Equatable, Sendable {
        public var pid: Int32
        /// Seconds since 1970; nil = until turned off.
        public var until: Double?
        public var display: Bool
        public init(pid: Int32, until: Double?, display: Bool) { self.pid = pid; self.until = until; self.display = display }

        public var state: CaffeineState { CaffeineState(until: until.map(Date.init(timeIntervalSince1970:)) ?? .distantFuture) }

        /// Still worth picking up after a restart: its process lives and its time has not run out.
        public func live(now: Date, alive: Bool) -> Bool { alive && (until.map { $0 > now.timeIntervalSince1970 } ?? true) }
    }

    /// The command that holds the Mac awake: idle sleep off, the display too when asked, for `seconds` or for good.
    public static func command(seconds: Int?, display: Bool) -> [String] {
        ["/usr/bin/caffeinate", "-i"] + (display ? ["-d"] : []) + (seconds.map { ["-t", String($0)] } ?? [])
    }

    /// On battery below `threshold` % (0 = never): time to let the Mac sleep.
    public static func batteryTooLow(percent: Int?, charging: Bool, threshold: Int) -> Bool {
        guard threshold > 0, let percent, !charging else { return false }
        return percent < threshold
    }
}
