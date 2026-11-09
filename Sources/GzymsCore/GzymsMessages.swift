import Foundation

// Messages from Gzyms itself, not from an app: what is new after an update, a macOS it was not tested on.
// The notes are whatsnew/<version>.md at the repo root, built in by scripts/gen-skill.sh (WhatsNew.gen.swift).

/// whatsnew/*.md as built in.
public let bundledWhatsNew = whatsNewFiles

/// The interactive tutorial in the browser, opened from the wizard, Settings → About and What's new.
public let tutorialURL = URL(string: "https://gzyms.dev/try/")!

/// The newest macOS major Gzyms was tried on. Raise it after a run on the next one.
public let testedMacOSMajor = 27

public enum GzymsMessage: Equatable, Sendable {
    case whatsNew(version: String, lines: [String])
    case untestedMacOS(major: Int)
}

/// What was already shown, kept in ~/Library/Application Support/Gzyms/messages.json.
public struct MessagesSeen: Codable, Equatable, Sendable {
    public var version: String?
    /// The untested macOS major already warned about.
    public var macOS: Int?
    /// App pairs ("a|b", bundle ids sorted) already told about for sending the same notification.
    public var duplicatePairs: [String]?
    /// "Stop these warnings": no more duplicate messages.
    public var duplicatesOff: Bool?
    /// The groups seen sending the same notification, for Settings → Debug.
    public var duplicateGroups: [DuplicateGroup]?
    public init(version: String? = nil, macOS: Int? = nil, duplicatePairs: [String]? = nil, duplicatesOff: Bool? = nil,
                duplicateGroups: [DuplicateGroup]? = nil) {
        self.version = version; self.macOS = macOS; self.duplicatePairs = duplicatePairs; self.duplicatesOff = duplicatesOff
        self.duplicateGroups = duplicateGroups
    }
}

/// Apps that sent the same notification together: how often, and when last. Bundle ids only, never the text.
public struct DuplicateGroup: Codable, Equatable, Sendable {
    /// Bundle ids, sorted.
    public var apps: [String]
    public var count: Int
    public var last: Date
    public init(apps: [String], count: Int, last: Date) { self.apps = apps; self.count = count; self.last = last }
}

/// Every pair of apps in the group, as "a|b" with the ids sorted.
public func appPairs(_ apps: [String]) -> [String] {
    let s = Array(Set(apps)).sorted()
    return s.indices.flatMap { i in s[(i + 1)...].map { "\(s[i])|\($0)" } }
}

/// A group of apps sent the same notification: counts it for Settings → Debug (even when the user stopped the warnings)
/// and says which apps to tell about, once per pair. `tell` is empty when the user stopped them or every pair was told already:
/// it lists the apps in a pair not told yet, and all the group's pairs are remembered.
public func recordDuplicates(apps: [String], at now: Date, seen: MessagesSeen) -> (tell: [String], seen: MessagesSeen) {
    let group = Array(Set(apps)).sorted()
    var next = seen
    var groups = seen.duplicateGroups ?? []
    if let i = groups.firstIndex(where: { $0.apps == group }) {
        groups[i].count += 1; groups[i].last = now
    } else {
        groups.append(DuplicateGroup(apps: group, count: 1, last: now))
    }
    next.duplicateGroups = groups
    guard seen.duplicatesOff != true else { return ([], next) }
    let told = Set(seen.duplicatePairs ?? [])
    let fresh = appPairs(group).filter { !told.contains($0) }
    guard !fresh.isEmpty else { return ([], next) }
    next.duplicatePairs = Array(told.union(appPairs(group))).sorted()
    return (Array(Set(fresh.flatMap { $0.split(separator: "|").map(String.init) })).sorted(), next)
}

extension MessagesSeen {
    /// Takes a group off the list and tells its pairs again if they come back.
    public func forgetting(group apps: [String]) -> MessagesSeen {
        var next = self
        next.duplicateGroups = duplicateGroups?.filter { $0.apps != apps }
        let gone = Set(appPairs(apps))
        next.duplicatePairs = duplicatePairs?.filter { !gone.contains($0) }
        return next
    }
}

/// The notification Gzyms posts for those apps; it opens Settings → Debug.
public func duplicateNotice(names: [String]) -> (title: String, body: String) {
    ("Apps send the same notification", "\(joinNames(names)). See Debug.")
}

/// Id of that notification: clicking it opens Settings → Debug instead of a link.
public let duplicateNoticeID = "gzyms-duplicates"

/// Id of the notification after an unlock: clicking it opens a bar list instead of a link.
public let awayNoticeID = "gzyms-away"

/// After an unlock: what came while the screen was locked and still waits, on screen or in a list, and the bar list
/// with most of it ("app:<bundle id>", else "bell"). nil when nothing came.
/// shortcut: a plugin's notes count toward the 🔔 even when its pill keeps them, add pill keys if plugins post a lot while away.
public func awayNotice(waiting: [GzymsNotification], since: Date, onBar: Set<String>) -> (title: String, list: String)? {
    let came = waiting.filter { !$0.compact && $0.id != awayNoticeID && $0.at >= since }
    let lists = Dictionary(grouping: came) { n in n.app.flatMap { onBar.contains($0) ? "app:\($0)" : nil } ?? "bell" }
    guard let top = lists.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) else { return nil }
    return ("\(came.count) notification\(came.count == 1 ? "" : "s") while you were away", top.key)
}

/// "A", "A and B", "A, B and C".
public func joinNames(_ names: [String]) -> String {
    guard let last = names.last, names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " and " + last
}

/// `a` is a later version than `b`, compared number by number; a missing part counts as 0.
public func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
        if l != r { return l > r }
    }
    return false
}

/// The "- " lines of a whatsnew file.
public func whatsNewLines(_ md: String) -> [String] {
    md.split(separator: "\n").filter { $0.hasPrefix("- ") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
}

/// The highest version that has notes; `gzyms message whats-new` shows it.
public func newestWhatsNew(_ notes: [String: String] = bundledWhatsNew) -> (version: String, lines: [String])? {
    notes.keys.max { isNewer($1, than: $0) }.map { ($0, whatsNewLines(notes[$0]!)) }
}

/// What to show at launch and what to remember. The very first launch shows no notes: the setup wizard greets.
public func launchMessages(seen: MessagesSeen?, version: String, macOS: Int, testedMacOS: Int = testedMacOSMajor,
                           notes: [String: String] = bundledWhatsNew) -> (show: [GzymsMessage], seen: MessagesSeen) {
    var show: [GzymsMessage] = []
    var next = seen ?? MessagesSeen()
    if let last = seen?.version, isNewer(version, than: last), let md = notes[version] {
        let lines = whatsNewLines(md)
        if !lines.isEmpty { show.append(.whatsNew(version: version, lines: lines)) }
    }
    if seen?.version == nil || isNewer(version, than: seen?.version ?? "") { next.version = version }
    if macOS > testedMacOS, seen?.macOS != macOS {
        show.append(.untestedMacOS(major: macOS))
        next.macOS = macOS
    }
    return (show, next)
}
