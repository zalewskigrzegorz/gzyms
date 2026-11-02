import Foundation

/// What macOS says is playing (its Now Playing, the same as Control Center's), from any app: Music, Spotify, a browser.
public struct NowPlaying: Equatable, Sendable {
    public var title: String, artist: String, album: String
    /// The app that plays (a browser tab reports its browser, not WebKit).
    public var app: String, appName: String
    public var playing: Bool
    /// `elapsed` seconds were true at `at` (seconds since 1970); it runs on from there while playing.
    public var elapsed: Double, duration: Double, at: Double, rate: Double
    public var artworkID: String
    /// The other apps with something to play (a film behind the music), for the popup. Empty from the osascript reader.
    public var others: [MediaSource]

    public init(title: String, artist: String = "", album: String = "", app: String = "", appName: String = "", playing: Bool,
                elapsed: Double = 0, duration: Double = 0, at: Double = 0, rate: Double = 1, artworkID: String = "",
                others: [MediaSource] = []) {
        self.title = title; self.artist = artist; self.album = album; self.app = app; self.appName = appName; self.playing = playing
        self.elapsed = elapsed; self.duration = duration; self.at = at; self.rate = rate; self.artworkID = artworkID
        self.others = others
    }

    /// "Artist – Title", or the title alone.
    public var line: String { artist.isEmpty ? title : "\(artist) – \(title)" }

    public func position(now: Double) -> Double {
        let p = elapsed + (playing ? max(0, now - at) * (rate > 0 ? rate : 1) : 0)
        return duration > 0 ? min(p, duration) : p
    }

    /// Paused this long, the pill leaves the bar.
    public static let idleAfter: Double = 300

    public func shown(now: Double) -> Bool { playing || now - at < Self.idleAfter }
}

/// An app with a media session that is not macOS's Now Playing. macOS steers only Now Playing, so this one can only
/// be gone to.
public struct MediaSource: Equatable, Sendable, Decodable {
    public var app: String, appName: String, title: String, artist: String
    public var playing: Bool

    public init(app: String, appName: String, title: String, artist: String = "", playing: Bool) {
        self.app = app; self.appName = appName; self.title = title; self.artist = artist; self.playing = playing
    }

    public var line: String { artist.isEmpty ? title : "\(artist) – \(title)" }
}

/// One line of the reader: a state, or nothing playing.
public enum NowPlayingLine: Equatable, Sendable {
    case nothing
    case item(NowPlaying, artwork: Data?)
}

/// nil = not a line of the reader (garbage, a half line).
public func nowPlayingLine(_ json: String) -> NowPlayingLine? {
    let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
    if text == "null" { return .nothing }
    struct Raw: Decodable {
        var title, artist, album, app, appName, artId, artwork: String?
        var playing: Bool?
        var elapsed, duration, at, rate: Double?
        var others: [MediaSource]?
    }
    guard let r = try? JSONDecoder().decode(Raw.self, from: Data(text.utf8)), let title = r.title, !title.isEmpty else { return nil }
    let np = NowPlaying(title: title, artist: r.artist ?? "", album: r.album ?? "", app: r.app ?? "", appName: r.appName ?? "",
                        playing: r.playing ?? false, elapsed: r.elapsed ?? 0, duration: r.duration ?? 0, at: r.at ?? 0,
                        rate: r.rate ?? 1, artworkID: r.artId ?? "", others: r.others ?? [])
    return .item(np, artwork: r.artwork.flatMap { Data(base64Encoded: $0) })
}

/// The fallback reader, for when the native one (tools/media-reader in /usr/bin/perl) does not start: Now Playing
/// alone, no other sources. Run by `/usr/bin/osascript -l JavaScript`. Since macOS 15.4 only Apple-signed processes may read
/// MediaRemote, and osascript is one (checked on 27.0.1). It stays up and prints a JSON line on every change, so
/// nothing is started per tick. shortcut: Apple can close this door; then the reader dies, the pill goes, the log says why.
public let nowPlayingScript = #"""
ObjC.import('Foundation');
$.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
const R = $.NSClassFromString('MRNowPlayingRequest');
const out = $.NSFileHandle.fileHandleWithStandardOutput;
const K = 'kMRMediaRemoteNowPlayingInfo';
const say = s => out.writeData($(s + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
ObjC.import('unistd');
function run() {
let last = '', lastArt = '';
while (true) {
  // Gzyms gone (killed, crashed): launchd adopts us, so do not linger.
  if ($.getppid() === 1) return;
  // An override of Now Playing (or a stuck mediaremoted) leaves the item, the path or the client empty: read that
  // as nothing playing instead of dying on it.
  const item = R.localNowPlayingItem, info = item && item.nowPlayingInfo;
  const path = R.localNowPlayingPlayerPath, c = path && path.client;
  let s = null;
  if (info && info.js && c && c.js) {
    const v = k => { const o = info.objectForKey(K + k); return o.js === undefined ? null : ObjC.unwrap(o); };
    const at = v('Timestamp');
    s = { title: v('Title') || '', artist: v('Artist') || '', album: v('Album') || '',
          app: ObjC.unwrap(c.parentApplicationBundleIdentifier) || ObjC.unwrap(c.bundleIdentifier) || '',
          appName: ObjC.unwrap(c.displayName) || '', playing: !!ObjC.unwrap(R.localIsPlaying),
          elapsed: v('ElapsedTime') || 0, duration: v('Duration') || 0,
          at: at ? at.getTime() / 1000 : Date.now() / 1000, rate: v('PlaybackRate') || 0, artId: String(v('ArtworkIdentifier') || '') };
  }
  const line = JSON.stringify(s);
  if (line !== last) {
    last = line;
    if (s && s.artId && s.artId !== lastArt) {
      lastArt = s.artId;
      const art = info.objectForKey(K + 'ArtworkData');
      if (art.js) s.artwork = ObjC.unwrap(art.base64EncodedStringWithOptions(0));
    }
    say(JSON.stringify(s));
  }
  delay(1);
}
}
"""#

/// The keys macOS sends to whatever plays (NX_KEYTYPE_*).
public enum MediaCommand: Int32, Sendable {
    case playPause = 16, next = 17, previous = 18
}

/// What the player's popup asks for: a media key (it reaches the last used player only), or going to an app's
/// window that shows this title.
public enum MusicAction: Sendable { case key(MediaCommand), jump(app: String, title: String) }
