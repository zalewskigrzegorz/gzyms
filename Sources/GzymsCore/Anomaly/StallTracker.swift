import Foundation

/// When the main thread stops answering. Pure bookkeeping, no threads or clocks, so the rules are testable.
/// Reports at the threshold, then at 4×, 16×… so a long hang leaves a trail even if it never recovers
/// (same rule as HyprMac's `MainThreadStallTracker`).
public struct StallTracker: Sendable {
    public let threshold: TimeInterval
    private var pingSentAt: TimeInterval?
    var pingSent: TimeInterval? { pingSentAt }
    private var nextReport: TimeInterval = 0

    public init(threshold: TimeInterval) { self.threshold = threshold }

    /// `sendPing`: queue a ping on main. `blocked`: how long main has been silent, set only when a report is due.
    public mutating func tick(at now: TimeInterval) -> (sendPing: Bool, blocked: TimeInterval?) {
        guard let sent = pingSentAt else {
            pingSentAt = now
            nextReport = threshold
            return (true, nil)
        }
        let age = now - sent
        guard age >= nextReport else { return (false, nil) }
        nextReport *= 4
        return (false, age)
    }

    /// Main answered the ping.
    public mutating func pong() { pingSentAt = nil }
}

/// Too many panel rebuilds in a short time: the SketchyBar wake bug in numbers.
public struct RebuildStorm: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var times: [TimeInterval] = []

    public init(limit: Int, window: TimeInterval) { self.limit = limit; self.window = window }

    public mutating func record(at now: TimeInterval) -> Bool {
        times.append(now)
        times.removeAll { now - $0 > window }
        return times.count >= limit
    }
}
