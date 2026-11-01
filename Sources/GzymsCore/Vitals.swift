import Foundation

/// What the bar reports about itself once a second, for the HUD running in another process.
public struct Vitals: Codable, Equatable, Sendable {
    public var pid: Int32
    public var at: Date
    public var lagMs: Double
    public var panels: Int
    public var rebuilds: Int
    public var eventsPerSec: Double

    public init(pid: Int32, at: Date, lagMs: Double, panels: Int, rebuilds: Int, eventsPerSec: Double) {
        self.pid = pid; self.at = at; self.lagMs = lagMs; self.panels = panels
        self.rebuilds = rebuilds; self.eventsPerSec = eventsPerSec
    }
}

public enum VitalsState: Equatable, Sendable {
    case fresh(Vitals)
    case notAnswering(since: Date)
    case missing
}

/// Vitals older than 2 s mean the bar's main thread is not getting to its once-a-second write.
public func vitalsFreshness(_ v: Vitals?, now: Date) -> VitalsState {
    guard let v else { return .missing }
    return now.timeIntervalSince(v.at) <= 2 ? .fresh(v) : .notAnswering(since: v.at)
}

/// Events per second over a sliding window.
public struct RateCounter: Sendable {
    public let window: TimeInterval
    private var hits: [TimeInterval] = []

    public init(window: TimeInterval) { self.window = window }

    public mutating func hit(at now: TimeInterval) {
        hits.append(now)
        hits.removeAll { now - $0 > window }
    }

    public func perSecond(at now: TimeInterval) -> Double {
        Double(hits.filter { now - $0 <= window }.count) / window
    }
}

extension StallTracker {
    /// Main answered: the round trip of the outstanding ping, or nil if none was out.
    public mutating func pong(at now: TimeInterval) -> TimeInterval? {
        guard let sent = pingSent else { return nil }
        pong()
        return now - sent
    }
}
