import Foundation

/// A browser tab with video or audio, as the userscript (assets/gzyms-media.user.js) reports it once a second.
public struct BrowserTab: Equatable, Sendable, Decodable {
    public struct Media: Equatable, Sendable, Decodable {
        public var i: Int
        public var kind: String
        public var title: String
        public var playing: Bool
        public init(i: Int, kind: String = "video", title: String, playing: Bool) {
            self.i = i; self.kind = kind; self.title = title; self.playing = playing
        }
    }
    public var id: String, url: String, title: String
    /// The userscript's last problem ("play: NotAllowedError"), for the log.
    public var note: String
    public var media: [Media]

    public init(id: String, url: String, title: String = "", note: String = "", media: [Media]) {
        self.id = id; self.url = url; self.title = title; self.note = note; self.media = media
    }

    public var host: String {
        let h = URL(string: url)?.host() ?? url
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

/// What the userscript is told to do with one media element of its tab; `focus` brings the tab to the front.
public enum TabCommand: String, Sendable { case play, pause, toggle, next, previous, focus }

/// The tabs heard from lately. A tab reports every second, so one silent for 3 s is gone (closed, reloaded,
/// the browser quit). Media that never played (a muted preview, a page opened and left) stay out, and paused
/// media leave after `NowPlaying.idleAfter`, like a paused song. A tab is one entry: the media that plays, else the
/// one played last, even if an older userscript sends a whole feed of clips.
public struct TabBook: Sendable {
    private var tabs: [String: (tab: BrowserTab, seen: Double)] = [:]
    private var played: [String: Double] = [:]

    public init() {}

    public mutating func report(_ t: BrowserTab, now: Double) {
        tabs[t.id] = (t, now)
        for m in t.media where m.playing { played["\(t.id)#\(m.i)"] = now }
        tabs = tabs.filter { now - $0.value.seen < 60 }
        played = played.filter { now - $0.value < NowPlaying.idleAfter }
    }

    public func live(now: Double) -> [BrowserTab] {
        tabs.values.filter { now - $0.seen < 3 }.map(\.tab).sorted { $0.id < $1.id }.compactMap { t in
            var t = t
            let recent = t.media.compactMap { m in played["\(t.id)#\(m.i)"].flatMap { now - $0 < NowPlaying.idleAfter ? (m, $0) : nil } }
            guard let one = recent.first(where: { $0.0.playing }) ?? recent.max(by: { $0.1 < $1.1 }) else { return nil }
            t.media = [one.0]
            return t
        }
    }
}

/// One thing that plays, for the pill and its popup: macOS's Now Playing app, a browser tab, or another app.
public struct MediaItem: Equatable, Sendable, Identifiable {
    public enum Source: Equatable, Sendable {
        case nowPlaying
        /// An app that is not Now Playing: macOS steers it only through its own AppleScript, if it has one.
        case app
        case tab(String, media: Int)
    }
    public var source: Source
    /// The app's bundle id; empty for a tab.
    public var app: String
    /// The app's name or the tab's site.
    public var from: String
    public var title: String, artist: String
    public var playing: Bool
    /// Elapsed and duration; only Now Playing says.
    public var clock: NowPlaying?

    public init(source: Source, app: String = "", from: String, title: String, artist: String = "", playing: Bool, clock: NowPlaying? = nil) {
        self.source = source; self.app = app; self.from = from; self.title = title; self.artist = artist; self.playing = playing
        self.clock = clock
    }

    public var id: String {
        switch source {
        case .nowPlaying: "now"
        case .app: "app:\(app)"
        case .tab(let t, let i): "tab:\(t)#\(i)"
        }
    }

    public var line: String { artist.isEmpty ? title : "\(artist) – \(title)" }
    public var isTab: Bool { if case .tab = source { true } else { false } }
    /// Play, pause and next reach it.
    public var steerable: Bool { source != .app || Self.scriptable.contains(app) }

    /// Apps with `playpause`, `next track` and `previous track` in their AppleScript.
    public static let scriptable: Set<String> = ["com.apple.Music", "com.spotify.client"]
}

/// Everything the pill shows, in a fixed order so nothing jumps: Now Playing, the tabs, the other apps. Now Playing
/// and its others leave together once it has been paused for `NowPlaying.idleAfter`.
public func mediaItems(_ np: NowPlaying?, tabs: [BrowserTab], now: Double) -> [MediaItem] {
    let shown = np.flatMap { $0.shown(now: now) ? $0 : nil }
    var out: [MediaItem] = []
    if let np = shown {
        out.append(MediaItem(source: .nowPlaying, app: np.app, from: np.appName, title: np.title, artist: np.artist, playing: np.playing, clock: np))
    }
    for t in tabs {
        for m in t.media { out.append(MediaItem(source: .tab(t.id, media: m.i), from: t.host, title: m.title, playing: m.playing)) }
    }
    for o in shown?.others ?? [] {
        out.append(MediaItem(source: .app, app: o.app, from: o.appName, title: o.title, artist: o.artist, playing: o.playing))
    }
    return out
}

/// The pill's main item: the first that plays, else the first.
public func mainMedia(_ items: [MediaItem]) -> MediaItem? { items.first(where: \.playing) ?? items.first }

/// One HTTP/1.1 request on the loopback server.
public struct LoopbackRequest: Equatable, Sendable {
    public var method: String, path: String
    /// Lowercased names.
    public var headers: [String: String]
    public var body: Data

    /// nil while the request is still arriving; `.some(nil)` for one that can never be read.
    public static func parse(_ d: Data) -> LoopbackRequest?? {
        guard let end = d.range(of: Data("\r\n\r\n".utf8)) else { return d.count > 16 << 10 ? .some(nil) : nil }
        let head = String(decoding: d[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let line = head[0].split(separator: " ")
        guard line.count >= 2 else { return .some(nil) }
        var headers: [String: String] = [:]
        for h in head.dropFirst() {
            if let colon = h.firstIndex(of: ":") {
                headers[h[..<colon].lowercased()] = h[h.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= 1 << 20 else { return .some(nil) }
        let body = d[end.upperBound...]
        guard body.count >= length else { return nil }
        return LoopbackRequest(method: String(line[0]), path: String(line[1]), headers: headers, body: Data(body.prefix(length)))
    }
}

/// Gecko browsers whose profiles Settings → Hacks reads (~/Library/Application Support/<name>/Profiles/*/prefs.js).
public let geckoBrowsers = ["Firefox", "Vimma", "zen", "librewolf", "Floorp", "Waterfox"]

/// The profile turned `media.hardwaremediakeys.enabled` off: the browser leaves the media keys and macOS's Now Playing
/// to the music player. A pref left at its default is not in prefs.js at all, so absent means on.
public func mediaKeysOff(prefsJS: String) -> Bool {
    prefsJS.split(separator: "\n").contains { $0.hasPrefix(#"user_pref("media.hardwaremediakeys.enabled", false)"#) }
}
