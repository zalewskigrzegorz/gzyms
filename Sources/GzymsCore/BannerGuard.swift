/// Notification Center can stop drawing banners altogether until it is restarted (spike: after a closing panel was
/// parked). Then apps still deliver (the log signal) but no banner ever shows. `warns` after 3 signals in a row with
/// no banner between them, the first at least 2 minutes back. Only a warning: Gzyms never restarts NC itself.
/// Times are seconds; the caller counts only while `signal` is on and Gzyms's do not disturb is off.
public struct BannerGuard {
    /// Read by `gzyms debug`.
    public private(set) var firstSignal: Double?
    public private(set) var signals = 0
    public private(set) var warns = false

    public init() {}

    public mutating func signal(at t: Double) {
        if firstSignal == nil { firstSignal = t }
        signals += 1
        if let first = firstSignal, signals >= 3, t - first >= 120 { warns = true }
    }

    public mutating func banner(at _: Double) {
        firstSignal = nil
        signals = 0
        warns = false
    }
}
