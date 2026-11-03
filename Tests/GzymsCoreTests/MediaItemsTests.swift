import Foundation
import Testing
@testable import GzymsCore

private func tab(_ id: String, _ playing: Bool, url: String = "https://www.youtube.com/watch?v=1") -> BrowserTab {
    BrowserTab(id: id, url: url, media: [.init(i: 0, title: "Film \(id)", playing: playing)])
}

@Test func theUserscriptReportDecodes() throws {
    let json = #"{"id":"a1","url":"https://www.youtube.com/watch?v=x","title":"Film - YouTube","note":"","media":[{"i":0,"kind":"video","playing":true,"title":"Film"}]}"#
    let t = try JSONDecoder().decode(BrowserTab.self, from: Data(json.utf8))
    #expect(t.host == "youtube.com")
    #expect(t.media == [.init(i: 0, kind: "video", title: "Film", playing: true)])
}

@Test func aTabShowsOnceItPlayedAndLeavesWhenSilentOrIdle() {
    var book = TabBook()
    book.report(tab("a", false), now: 100)
    #expect(book.live(now: 100).isEmpty)  // a page opened and left: its video never played
    book.report(tab("a", true), now: 101)
    #expect(book.live(now: 101).map(\.id) == ["a"])
    #expect(book.live(now: 104).isEmpty)  // no report for 3 s: closed or reloaded
    book.report(tab("a", false), now: 200)
    #expect(book.live(now: 200).map(\.id) == ["a"])  // paused stays a while, like a song
    book.report(tab("a", false), now: 101 + NowPlaying.idleAfter)
    #expect(book.live(now: 101 + NowPlaying.idleAfter).isEmpty)
}

@Test func itemsKeepAFixedOrderAndTheMainOneIsTheFirstThatPlays() {
    var np = NowPlaying(title: "Song", artist: "Band", app: "rocks.spotifast.Spotifast", appName: "Spotifast", playing: false, at: 1000)
    np.others = [MediaSource(app: "com.apple.Music", appName: "Music", title: "Other", playing: false),
                 MediaSource(app: "com.apple.podcasts", appName: "Podcasts", title: "Talk", playing: false)]
    let items = mediaItems(np, tabs: [tab("t", true)], now: 1010)
    #expect(items.map(\.id) == ["now", "tab:t#0", "app:com.apple.Music", "app:com.apple.podcasts"])
    #expect(items[1].from == "youtube.com")
    #expect(mainMedia(items)?.id == "tab:t#0")
    // Music.app and Spotify answer AppleScript; any other app only Go to.
    #expect(items.map(\.steerable) == [true, true, true, false])
    // Paused for long, Now Playing and its others leave; the tab stays.
    #expect(mediaItems(np, tabs: [tab("t", true)], now: 1000 + NowPlaying.idleAfter).map(\.id) == ["tab:t#0"])
    #expect(mainMedia([]) == nil)
}

@Test func loopbackRequestsWaitForTheirBodyAndRejectJunk() throws {
    let head = "POST /report HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Gzyms: 1\r\nContent-Length: 4\r\n\r\n"
    #expect(LoopbackRequest.parse(Data("POST /rep".utf8)) == .none)  // still arriving
    #expect(LoopbackRequest.parse(Data((head + "ab").utf8)) == .none)
    let parsed = try #require(LoopbackRequest.parse(Data((head + "abcd").utf8)))
    let r = try #require(parsed)
    #expect(r.method == "POST" && r.path == "/report" && r.headers["x-gzyms"] == "1" && r.body == Data("abcd".utf8))
    #expect(LoopbackRequest.parse(Data("x\r\n\r\n".utf8)) == .some(nil))
    #expect(LoopbackRequest.parse(Data("GET / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)) == .some(nil))
}

@Test func browserMediaIsOffUntilTurnedOn() {
    #expect(!loadConfig(toml: nil).config.browserMedia)
    let on = loadConfig(toml: "[hacks]\nbrowser_media = true")
    #expect(on.config.browserMedia && on.problems.isEmpty)
}

@Test func theMediaKeysPrefIsReadFromPrefsJS() {
    #expect(mediaKeysOff(prefsJS: "user_pref(\"a\", 1);\nuser_pref(\"media.hardwaremediakeys.enabled\", false);\n"))
    #expect(!mediaKeysOff(prefsJS: "user_pref(\"media.hardwaremediakeys.enabled\", true);\n"))
    #expect(!mediaKeysOff(prefsJS: "// user_pref(\"media.hardwaremediakeys.enabled\", false);\n"))
    #expect(!mediaKeysOff(prefsJS: ""))
}
