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

    private var recent: [(app: String, words: Set<String>, at: TimeInterval)] = []
    private var counts: [String: Int] = [:]

    public init() {}

    /// The apps (sorted, with `app`) that posted this text within the window, and how often that same set was seen
    /// since launch; nil when no other app did.
    public mutating func record(app: String, title: String, body: String?, at now: TimeInterval) -> (apps: [String], count: Int)? {
        recent.removeAll { now - $0.at > Self.window }
        let w = words(title, body)
        guard w.count >= Self.minWords else { return nil }
        let others = Set(recent.filter { $0.app != app && Self.close($0.words, w) }.map(\.app))
        recent.append((app, w, now))
        guard !others.isEmpty else { return nil }
        let apps = others.union([app]).sorted()
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
