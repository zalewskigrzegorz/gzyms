import Foundation

/// Two or more different apps posting the same (or nearly the same) notification at the same moment: a calendar
/// installed twice, four calendars on one account. Gzyms never drops one itself, it tells the user once.
/// Only the words are compared and kept, as a set of tokens, and never leave this struct: nothing logs the text.
public struct DuplicateDetector: Sendable {
    /// Seconds. The log and the database hand Gzyms a notification up to ~5 s after the app posted it, and two apps
    /// rarely land on the same second: 10 s covers that spread and stays far from a reminder repeating a minute later.
    public static let window: TimeInterval = 10
    /// shortcut: a text with fewer words is never a match ("New message" from Mail and Messages), upgrade if a short duplicate slips by.
    static let minWords = 3
    /// Share of words two texts have in common (Jaccard). 1 = same words, 0.8 lets "10:00" gain an "AM".
    static let similarity = 0.8

    /// Seconds. Calendar apps remind about one meeting at their own offsets (10, 5, 0 min before) and in their own words,
    /// so a reminder whose title names a meeting from the calendar is matched by that meeting for this long.
    public static let meetingWindow: TimeInterval = 15 * 60

    private var recent: [(app: String, words: Set<String>, at: TimeInterval)] = []
    private var meetingApps: [String: (apps: Set<String>, at: TimeInterval)] = [:]
    private var counts: [String: Int] = [:]

    public init() {}

    /// The apps (sorted, with `app`) that posted this text within the window, or a reminder about the same meeting
    /// (`meetings`: titles of meetings starting about now), and how often that same set was seen since launch;
    /// nil when no other app did.
    public mutating func record(app: String, title: String, body: String?, meetings: [String] = [],
                                at now: TimeInterval) -> (apps: [String], count: Int)? {
        meetingApps = meetingApps.filter { now - $0.value.at <= Self.meetingWindow }
        // Only the title: Slack's title is the sender, so a chat message saying "sync" is not the Sync meeting.
        let titleWords = words(title, nil)
        if let m = meetings.map({ words($0, nil) }).first(where: { !$0.isEmpty && $0.isSubset(of: titleWords) }) {
            let key = m.sorted().joined(separator: " ")
            var e = meetingApps[key] ?? ([], now)
            guard e.apps.insert(app).inserted else { return nil }  // the same app's next alert about it
            meetingApps[key] = e
            return e.apps.count > 1 ? hit(e.apps) : nil
        }
        recent.removeAll { now - $0.at > Self.window }
        let w = words(title, body)
        guard w.count >= Self.minWords else { return nil }
        let others = Set(recent.filter { $0.app != app && Self.close($0.words, w) }.map(\.app))
        recent.append((app, w, now))
        guard !others.isEmpty else { return nil }
        return hit(others.union([app]))
    }

    private mutating func hit(_ set: Set<String>) -> (apps: [String], count: Int) {
        let apps = set.sorted()
        let key = apps.joined(separator: ",")
        counts[key, default: 0] += 1
        return (apps, counts[key]!)
    }

    /// Case, accents and punctuation do not matter.
    func words(_ title: String, _ body: String?) -> Set<String> {
        let text = "\(title) \(body ?? "")".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    static func close(_ a: Set<String>, _ b: Set<String>) -> Bool {
        Double(a.intersection(b).count) / Double(a.union(b).count) >= similarity
    }
}
