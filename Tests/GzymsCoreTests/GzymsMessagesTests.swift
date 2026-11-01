import Testing
@testable import GzymsCore

@Test func versionsCompareByNumbers() {
    #expect(isNewer("0.0.10", than: "0.0.9"))
    #expect(isNewer("1.0.1", than: "1.0"))
    #expect(!isNewer("1.0", than: "1.0.0"))
    #expect(!isNewer("0.0.1", than: "0.0.2"))
}

@Test func whatsNewTakesTheBulletLines() {
    #expect(whatsNewLines("# 0.0.2\n\n- One\n-  Two \nnot this\n") == ["One", "Two"])
}

private let notes = ["0.0.2": "- Banners queue up\n- Leader keys\n"]

@Test func firstLaunchShowsNothingAndRemembersTheVersion() {
    let r = launchMessages(seen: nil, version: "0.0.2", macOS: 27, testedMacOS: 27, notes: notes)
    #expect(r.show.isEmpty)
    #expect(r.seen == MessagesSeen(version: "0.0.2", macOS: nil))
}

@Test func aNewerVersionShowsItsNotes() {
    let r = launchMessages(seen: MessagesSeen(version: "0.0.1"), version: "0.0.2", macOS: 27, testedMacOS: 27, notes: notes)
    #expect(r.show == [.whatsNew(version: "0.0.2", lines: ["Banners queue up", "Leader keys"])])
    #expect(r.seen.version == "0.0.2")
}

@Test func theSameOrAnOlderVersionShowsNothing() {
    for v in ["0.0.2", "0.0.1"] {
        let r = launchMessages(seen: MessagesSeen(version: "0.0.2"), version: v, macOS: 27, testedMacOS: 27, notes: notes)
        #expect(r.show.isEmpty)
    }
}

@Test func aNewerVersionWithoutNotesShowsNothingButIsRemembered() {
    let r = launchMessages(seen: MessagesSeen(version: "0.0.2"), version: "0.0.3", macOS: 27, testedMacOS: 27, notes: notes)
    #expect(r.show.isEmpty)
    #expect(r.seen.version == "0.0.3")
}

@Test func anUntestedMacOSWarnsOncePerMajor() {
    let first = launchMessages(seen: MessagesSeen(version: "0.0.2"), version: "0.0.2", macOS: 28, testedMacOS: 27, notes: notes)
    #expect(first.show == [.untestedMacOS(major: 28)])
    let again = launchMessages(seen: first.seen, version: "0.0.2", macOS: 28, testedMacOS: 27, notes: notes)
    #expect(again.show.isEmpty)
    let next = launchMessages(seen: again.seen, version: "0.0.2", macOS: 29, testedMacOS: 27, notes: notes)
    #expect(next.show == [.untestedMacOS(major: 29)])
}

@Test func theTestedMacOSNeverWarns() {
    #expect(launchMessages(seen: nil, version: "0.0.2", macOS: 27, testedMacOS: 27, notes: notes).show.isEmpty)
    #expect(launchMessages(seen: nil, version: "0.0.2", macOS: 26, testedMacOS: 27, notes: notes).show.isEmpty)
}

@Test func firstLaunchOnAnUntestedMacOSStillWarns() {
    #expect(launchMessages(seen: nil, version: "0.0.2", macOS: 28, testedMacOS: 27, notes: notes).show == [.untestedMacOS(major: 28)])
}

@Test func theNewestNotesAreTheHighestVersion() {
    #expect(newestWhatsNew(["0.0.9": "- a", "0.0.10": "- b"])?.version == "0.0.10")
    #expect(newestWhatsNew([:]) == nil)
}
