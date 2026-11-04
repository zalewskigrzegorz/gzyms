import Testing
@testable import GzymsCore

@Test func guardStaysQuietOnTwoSignals() {
    var g = BannerGuard()
    g.signal(at: 0)
    g.signal(at: 300)
    #expect(!g.warns)
}

@Test func guardWarnsOnThreeSignalsOverTwoMinutesWithoutABanner() {
    var g = BannerGuard()
    g.signal(at: 0)
    g.signal(at: 60)
    g.signal(at: 119)
    #expect(!g.warns)  // three, but not two minutes yet
    g.signal(at: 130)
    #expect(g.warns)
}

@Test func guardResetsOnABanner() {
    var g = BannerGuard()
    g.signal(at: 0)
    g.signal(at: 60)
    g.banner(at: 61)
    g.signal(at: 130)
    #expect(!g.warns)
    g.signal(at: 200)
    g.signal(at: 260)
    #expect(g.warns)
    g.banner(at: 261)
    #expect(!g.warns)
}
