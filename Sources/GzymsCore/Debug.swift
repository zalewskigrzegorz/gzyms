import Foundation

/// `gzyms debug`: what the running bar knows about itself, one fact per line. The bar holds Full Disk Access and
/// Accessibility, so it answers; the command only asks. Never the text of a notification: apps, times and counts only.
public struct DebugReport: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var key: String
        public var value: String
    }

    public private(set) var lines: [Line] = []

    public init() {}

    public mutating func add(_ key: String, _ value: String) { lines.append(Line(key: key, value: value)) }
    public mutating func add(_ key: String, _ on: Bool) { add(key, on ? "yes" : "no") }
    public mutating func add(_ other: DebugReport) { lines += other.lines }

    /// `key: value`, one per line.
    public func text() -> String { lines.map { "\($0.key): \($0.value)" }.joined(separator: "\n") + "\n" }

    /// One flat object, every value a string.
    public func json() -> Data {
        let object = Dictionary(lines.map { ($0.key, $0.value) }, uniquingKeysWith: { _, b in b })
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])) ?? Data("{}".utf8)
    }

    /// What the bar hands back: pairs, so the order survives.
    public func wire() -> Data { (try? JSONSerialization.data(withJSONObject: lines.map { [$0.key, $0.value] })) ?? Data("[]".utf8) }

    public init?(wire: Data) {
        guard let pairs = try? JSONSerialization.jsonObject(with: wire) as? [[String]] else { return nil }
        for p in pairs where p.count == 2 { add(p[0], p[1]) }
    }
}

public let debugTopics = ["notifications", "keys"]

/// `gzyms debug [notifications|keys] [--json]`: no topic = all of them. nil = not a valid call.
public func debugArguments(_ args: [String]) -> (topics: [String], json: Bool)? {
    let json = args.contains("--json")
    let words = args.filter { $0 != "--json" }
    guard words.allSatisfy(debugTopics.contains) else { return nil }
    return (words.isEmpty ? debugTopics : words, json)
}

/// The request the CLI posts: an id that names the reply file, then the topics.
public func debugRequest(id: String, topics: [String]) -> String { ([id] + topics).joined(separator: " ") }

public func debugRequestParts(_ message: String) -> (id: String, topics: [String])? {
    let parts = message.split(separator: " ").map(String.init)
    guard let id = parts.first, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
    let topics = parts.dropFirst().filter(debugTopics.contains)
    return (id, topics.isEmpty ? debugTopics : Array(topics))
}

extension NCAppSettings {
    /// What Gzyms reads from macOS for one app, in the words of System Settings → Notifications.
    public var debugLine: String {
        if unsupported { return "unsupported, macOS lets nothing be set for it" }
        if hidden { return "system agent, not listed in System Settings" }
        let style = !desktop ? "off" : persistent ? "persistent" : "temporary"
        let shown = ["default", "never", "unlocked", "always"]
        let preview = (previews >= 0 && previews < shown.count ? shown[previews] : "\(previews)") + (previews == 0 && defaultHidden ? " (never)" : "")
        let line = "allow=\(allowed ? "on" : "off") banners=\(style) center=\(center ? "on" : "off") sound=\(sound ? "on" : "off") previews=\(preview)"
        return problems.isEmpty ? line : line + ", problems: " + problems.joined(separator: ", ")
    }
}

/// "12 s ago", "3 min ago", "2 h ago"; nil date = "never".
public func debugAgo(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "never" }
    let s = max(0, Int(now.timeIntervalSince(date)))
    return s < 90 ? "\(s) s ago" : s < 5400 ? "\(s / 60) min ago" : "\(s / 3600) h ago"
}
