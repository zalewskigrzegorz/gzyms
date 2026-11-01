import Testing
@testable import GzymsCore

@Test func hideComesBackAfterThirtySeconds() {
    var h = HUDHide()
    h.hide(at: 100)
    #expect(h.isHidden)
    let early = h.dueToShow(at: 129), onTime = h.dueToShow(at: 130), again = h.dueToShow(at: 131)
    #expect(!early)
    #expect(onTime)
    #expect(!again)
    #expect(!h.isHidden)
}

@Test func commandShowsWhenHiddenQuitsWhenShown() {
    var h = HUDHide()
    let shown = h.command()
    h.hide(at: 0)
    let hidden = h.command(), after = h.command()
    #expect(shown == .quit)
    #expect(hidden == .show)
    #expect(after == .quit)
}
