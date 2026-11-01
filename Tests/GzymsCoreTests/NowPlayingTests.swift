import Foundation
import Testing
@testable import GzymsCore

@Test func readerLineBecomesNowPlaying() throws {
    let art = Data([1, 2, 3]).base64EncodedString()
    let json = #"{"title":"Song","artist":"Band","album":"LP","app":"com.spotify.client","appName":"Spotify","playing":true,"elapsed":30,"duration":200,"at":1000,"rate":1,"artId":"7","artwork":"\#(art)"}"#
    guard case .item(let np, let artwork) = try #require(nowPlayingLine(json)) else { Issue.record("not an item"); return }
    #expect(np.line == "Band – Song")
    #expect(np.app == "com.spotify.client" && np.appName == "Spotify")
    #expect(np.artworkID == "7")
    #expect(artwork == Data([1, 2, 3]))
    #expect(nowPlayingLine("null") == .nothing)
    #expect(nowPlayingLine("{\"title\":\"\"}") == nil)  // nothing to show
    #expect(nowPlayingLine("{\"tit") == nil)            // half a line
}

@Test func positionRunsOnWhilePlayingAndStopsAtTheEnd() {
    var np = NowPlaying(title: "x", playing: true, elapsed: 30, duration: 200, at: 1000)
    #expect(np.position(now: 1010) == 40)
    #expect(np.position(now: 5000) == 200)
    np.playing = false
    #expect(np.position(now: 1010) == 30)
    #expect(np.line == "x")
}

@Test func aPausedTrackLeavesTheBarAfterFiveMinutes() {
    let paused = NowPlaying(title: "x", playing: false, at: 1000)
    #expect(paused.shown(now: 1000 + 299))
    #expect(!paused.shown(now: 1000 + 300))
    #expect(NowPlaying(title: "x", playing: true, at: 0).shown(now: 99_999))
}
