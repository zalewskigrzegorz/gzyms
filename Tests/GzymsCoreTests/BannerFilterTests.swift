import Testing
@testable import GzymsCore

@Test func filterAcceptsANewBannerOnce() {
    var f = BannerFilter()
    func accept(_ u: String, _ t: Double) -> Bool { f.accept(uuid: u, panelOpen: false, now: t) }
    #expect(accept("A", 1))
    #expect(!accept("A", 2))
    #expect(accept("B", 2))
}

@Test func filterRejectsPanelRowsAndTheClosingPanel() {
    var f = BannerFilter()
    func accept(_ u: String, _ open: Bool, _ t: Double) -> Bool { f.accept(uuid: u, panelOpen: open, now: t) }
    #expect(!accept("row", true, 9.9))
    // AXExpanded is false ~0.2 s before the rows leave the tree: the closing panel's rows are not banners.
    #expect(!accept("row", false, 10))
    #expect(!accept("row", false, 10.79))
    #expect(accept("new", false, 10.81))
}

@Test func filterGraceStartsWhenThePanelCloses() {
    var f = BannerFilter()
    func accept(_ u: String, _ t: Double) -> Bool { f.accept(uuid: u, panelOpen: false, now: t) }
    f.note(panelOpen: true, now: 10)
    f.note(panelOpen: true, now: 20)
    // The grace counts from the first sweep that sees it closed, not from the last one that saw it open.
    #expect(!accept("row", 20.5))
    #expect(!accept("row2", 21.2))
    #expect(accept("row3", 21.31))
}

@Test func filterSkipsWhatWasUpAtStart() {
    var f = BannerFilter()
    func accept(_ u: String) -> Bool { f.accept(uuid: u, panelOpen: false, now: 1) }
    f.skipPresentAtStart = ["login-items"]
    #expect(!accept("login-items"))
    #expect(accept("other"))
}
