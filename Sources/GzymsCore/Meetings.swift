import Foundation

/// A calendar event worth a reminder: it has a video link. Times are seconds since 1970.
public struct Meeting: Equatable, Sendable {
    /// Event id plus start, so each occurrence of a recurring meeting is its own reminder and a moved one is new.
    public var id: String
    public var title: String
    public var start: Double
    public var end: Double
    public var link: String

    public init(id: String, title: String, start: Double, end: Double, link: String) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.link = link
    }
}

/// A calendar macOS knows, for the settings list. `key` ("Account/Title") is what `calendar.skip` holds.
public struct CalendarInfo: Hashable, Sendable {
    public var key: String, title: String, account: String
    public init(title: String, account: String) { self.title = title; self.account = account; key = "\(account)/\(title)" }
}

/// The first video-call link in the event's URL field, location or notes, in that order.
public func videoLink(url: String?, location: String?, notes: String?) -> String? {
    for text in [url, location, notes].compactMap({ $0 }) {
        for match in text.matches(of: /https?:\/\/[^\s<>"')\]]+/) {
            let link = String(match.output)
            guard let host = URL(string: link)?.host()?.lowercased() else { continue }
            let path = URL(string: link)?.path() ?? ""
            let video = host == "meet.google.com"
                || (host.hasSuffix("zoom.us") && (path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/s/")))
                || (host == "teams.microsoft.com" && path.contains("meetup-join")) || host == "teams.live.com"
                || (host == "app.slack.com" && path.contains("huddle"))
                || host.hasSuffix("webex.com")
                || host == "whereby.com" || host == "meet.jit.si"
            if video { return link }
        }
    }
    return nil
}

/// Which meeting reminder is on screen, from the meetings and the points (minutes before the start; negative = after).
/// A reminder never expires: join and dismiss end it, snooze waits for the next point. Pure, so every rule has a test.
public struct MeetingClock: Sendable {
    public struct Due: Equatable, Sendable {
        public var meeting: Meeting
        /// The point that brought it up: 3 = three minutes before, -3 = three minutes late.
        public var point: Int
    }

    /// Where a snoozed reminder comes back: the next step after the point it was snoozed at, whatever `points` says.
    /// So one "remind me" point stays one reminder, and snooze still has somewhere to go.
    public static let ladder = [5, 3, 0, -3]

    public var points: [Int]
    private var done: Set<String> = []
    private var snoozedAt: [String: Int] = [:]  // id → the point it was snoozed at

    public init(points: [Int] = [3]) { self.points = points }

    /// The reminder to show now: of the meetings past a point and not done, the one starting first.
    /// After the meeting ends nothing is shown for it.
    public func due(_ meetings: [Meeting], now: Double) -> Due? {
        meetings.filter { !done.contains($0.id) && now < $0.end }
            .compactMap { m in point(m, now: now).map { Due(meeting: m, point: $0) } }
            .min { $0.meeting.start < $1.meeting.start }
    }

    /// When to look again: the next point of any meeting still to come.
    public func nextCheck(_ meetings: [Meeting], now: Double) -> Double? {
        meetings.filter { !done.contains($0.id) }
            .flatMap { m in steps(m).map { m.start - Double($0) * 60 } }
            .filter { $0 > now }.min()
    }

    /// Joined or dismissed: no more reminders for this occurrence.
    public mutating func finish(_ id: String) { done.insert(id); snoozedAt[id] = nil }

    /// Back at the next point; with no point left it is done.
    public mutating func snooze(_ m: Meeting, now: Double) {
        guard let p = point(m, now: now) else { return }
        if Self.ladder.contains(where: { $0 < p }) { snoozedAt[m.id] = p } else { finish(m.id) }
    }

    /// What survives a bar restart (meetings.json): a meeting joined at 10:00 stays quiet after a 10:03 restart.
    public struct Saved: Codable, Equatable, Sendable {
        public var done: [String]
        public var snoozedAt: [String: Int]
    }

    /// Ids end in "@<start>": an occurrence that started over a day ago never reminds again, so it is dropped.
    public func saved(now: Double) -> Saved {
        let fresh = { (id: String) in id.split(separator: "@").last.flatMap { Double($0) }.map { $0 > now - 86400 } ?? false }
        return Saved(done: done.filter(fresh).sorted(), snoozedAt: snoozedAt.filter { fresh($0.key) })
    }

    public mutating func restore(_ s: Saved) { done = Set(s.done); snoozedAt = s.snoozedAt }

    /// The points that can still bring this meeting up: its own, or after a snooze the ladder steps below it.
    private func steps(_ m: Meeting) -> [Int] {
        snoozedAt[m.id].map { s in Self.ladder.filter { $0 < s } } ?? points
    }

    /// The latest point already reached (a Mac asleep across several points wakes to the last one only).
    private func point(_ m: Meeting, now: Double) -> Int? {
        steps(m).filter { m.start - Double($0) * 60 <= now }.min()
    }
}
