import Foundation

// Messages from Gzyms itself, not from an app: what is new after an update, a macOS it was not tested on.
// The notes are whatsnew/<version>.md at the repo root, built in by scripts/gen-skill.sh (WhatsNew.gen.swift).

/// whatsnew/*.md as built in.
public let bundledWhatsNew = whatsNewFiles

/// The interactive tutorial in the browser, opened from the wizard, the logo menu and What's new.
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
    public init(version: String? = nil, macOS: Int? = nil) { self.version = version; self.macOS = macOS }
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
