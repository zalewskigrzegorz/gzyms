import Foundation

/// When Gzyms may restart a hung Notification Center (`BannerGuard` warned). The automatic restart is limited to once
/// per 10 minutes and only once per hang: if no banner shows after a restart, NC is still hung and Gzyms stops and
/// warns. The Settings button has no limit. Times are system uptime seconds.
public struct NCRestartPolicy {
    public static let minGap = 600.0
    public private(set) var last: Double?
    public private(set) var count = 0
    /// A restart happened and no banner has shown since.
    public private(set) var stillHung = false

    public init() {}

    public func mayAutoRestart(enabled: Bool, at t: Double) -> Bool {
        guard enabled, !stillHung else { return false }
        return last.map { t - $0 >= Self.minGap } ?? true
    }

    public mutating func restarted(at t: Double) {
        last = t
        count += 1
        stillHung = true
    }

    public mutating func bannerShown() { stillHung = false }
}

/// The automatic restarts of today, for "Restarted 2 times today" in Settings. Kept in a file, so a Gzyms restart
/// does not zero it; older days drop out.
public func restartsToday(_ times: [Date], now: Date, calendar: Calendar = .current) -> [Date] {
    times.filter { calendar.isDate($0, inSameDayAs: now) }
}

/// A macOS Focus (Sleep, Work, Do Not Disturb) holds banners back while `~/Library/DoNotDisturb/DB/Assertions.json`
/// has an assertion record. Then no banner is not a hung Notification Center.
public func focusIsOn(assertions: Data) -> Bool {
    guard let root = try? JSONSerialization.jsonObject(with: assertions) as? [String: Any],
          let data = root["data"] as? [[String: Any]] else { return false }
    return data.contains { !(($0["storeAssertionRecords"] as? [Any]) ?? []).isEmpty }
}
