import Testing
@testable import GzymsCore

private let rows = ["Permissions grants accessibility", "Do Not Disturb on dnd", "Test banner notification", "Sounds audio",
                    "Slack · Krzysztof Nowak · deploy done", "Slack · Anna · lunch?", "Quit gzyms"]

private func rank(_ q: String) -> [String] { paletteRank(q, rows) { $0 } }

@Test func wordStartsAndLettersInOrderFit() {
    #expect(rank("perm").first == "Permissions grants accessibility")
    #expect(rank("dnd").first == "Do Not Disturb on dnd")
    #expect(rank("tst bnr") == ["Test banner notification"])
    #expect(rank("quit") == ["Quit gzyms"])
}

@Test func everyWordMustFitAndNotificationsMatchAppAndSender() {
    #expect(rank("slack krzysz") == ["Slack · Krzysztof Nowak · deploy done"])
    #expect(rank("slack").count == 2)
    #expect(rank("slack zzz").isEmpty)
    #expect(rank("xyz").isEmpty)
}

@Test func titleBeatsAMentionLaterAndEmptyKeepsAll() {
    #expect(paletteRank("sound", ["Banner with sound", "Sounds audio"]) { $0 } == ["Sounds audio", "Banner with sound"])
    #expect(rank("") == rows)
    #expect(rank("  ") == rows)
}

@Test func dndMinutesFromTheQuery() {
    #expect(paletteDNDMinutes("dnd 1h") == 60)
    #expect(paletteDNDMinutes("DND 30") == 30)
    #expect(paletteDNDMinutes("dnd 45m") == 45)
    #expect(paletteDNDMinutes("dnd 1h30") == 90)
    #expect(paletteDNDMinutes("dnd 0") == nil)
    #expect(paletteDNDMinutes("dnd h") == nil)
    #expect(paletteDNDMinutes("dnd") == nil)
    #expect(paletteDNDMinutes("dnd soon") == nil)
}

@Test func spaceOpensThePaletteAndEndsTheMode() {
    var n = KeyNav()
    _ = n.handle(.leaderDown([]), now: 0)
    _ = n.handle(.leaderUp, now: 0)
    #expect(NavKey(keyCode: 49, modified: false) == .space)
    let r = n.handle(.key(.space), now: 1)
    #expect(r.swallow && r.actions == [.palette, .exit])
    #expect(!n.on)
}
