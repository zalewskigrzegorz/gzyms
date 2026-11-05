import Foundation
import Testing
@testable import GzymsCore

private let standup = ("Standup with the team", "Starts in 5 minutes")

@Test func sameTextFromTwoAppsIsADuplicate() {
    var d = DuplicateDetector()
    #expect(d.record(app: "com.apple.iCal", title: standup.0, body: standup.1, at: 0) == nil)
    let hit = d.record(app: "com.flexibits.fantastical2.mac", title: standup.0, body: standup.1, at: 1)
    #expect(hit?.apps == ["com.apple.iCal", "com.flexibits.fantastical2.mac"])
    #expect(hit?.count == 1)
}

@Test func nearlyTheSameTextMatchesDespiteCasePunctuationAndAccents() {
    var d = DuplicateDetector()
    _ = d.record(app: "a", title: "Standup with the team", body: "Starts at 10:00", at: 0)
    #expect(d.record(app: "b", title: "STANDUP — with the team!", body: "starts at 10:00 AM", at: 2)?.apps == ["a", "b"])
    var e = DuplicateDetector()
    _ = e.record(app: "a", title: "Spotkanie zespołu", body: "Za pięć minut", at: 0)
    #expect(e.record(app: "b", title: "Spotkanie zespołu", body: "Za piec minut", at: 1) != nil)
}

@Test func differentTextIsNotADuplicate() {
    var d = DuplicateDetector()
    _ = d.record(app: "a", title: "Standup with the team", body: "Starts in 5 minutes", at: 0)
    #expect(d.record(app: "b", title: "Lunch with Anna", body: "Starts in 5 minutes", at: 1) == nil)
}

@Test func sameAppTwiceIsNotADuplicate() {
    var d = DuplicateDetector()
    _ = d.record(app: "a", title: standup.0, body: standup.1, at: 0)
    #expect(d.record(app: "a", title: standup.0, body: standup.1, at: 1) == nil)
}

@Test func outsideTheWindowIsNotADuplicate() {
    var d = DuplicateDetector()
    _ = d.record(app: "a", title: standup.0, body: standup.1, at: 0)
    #expect(d.record(app: "b", title: standup.0, body: standup.1, at: DuplicateDetector.window + 1) == nil)
    var e = DuplicateDetector()
    _ = e.record(app: "a", title: standup.0, body: standup.1, at: 0)
    #expect(e.record(app: "b", title: standup.0, body: standup.1, at: DuplicateDetector.window) != nil)
}

@Test func shortTextsNeverMatch() {
    var d = DuplicateDetector()
    _ = d.record(app: "com.apple.mail", title: "New message", body: nil, at: 0)
    #expect(d.record(app: "com.apple.MobileSMS", title: "New message", body: nil, at: 1) == nil)
}

@Test func fourAppsGrowTheGroupAndTheCountIsPerGroup() {
    var d = DuplicateDetector()
    _ = d.record(app: "a", title: standup.0, body: standup.1, at: 0)
    #expect(d.record(app: "b", title: standup.0, body: standup.1, at: 0.5)?.apps == ["a", "b"])
    #expect(d.record(app: "c", title: standup.0, body: standup.1, at: 1)?.apps == ["a", "b", "c"])
    #expect(d.record(app: "d", title: standup.0, body: standup.1, at: 1.5)?.apps == ["a", "b", "c", "d"])
    // The same pair again, a minute later: the count of that group goes up.
    _ = d.record(app: "a", title: standup.0, body: standup.1, at: 60)
    #expect(d.record(app: "b", title: standup.0, body: standup.1, at: 61)?.count == 2)
}

@Test func pairsAreSortedAndUnique() {
    #expect(appPairs(["b", "a", "b"]) == ["a|b"])
    #expect(appPairs(["c", "a", "b"]) == ["a|b", "a|c", "b|c"])
    #expect(appPairs(["a"]).isEmpty)
}

@Test func aPairIsToldOnceInEitherOrder() throws {
    let first = try #require(duplicateMessage(apps: ["b", "a"], seen: MessagesSeen(version: "0.0.1")))
    #expect(first.show == .duplicateApps(apps: ["a", "b"]))
    #expect(first.seen.duplicatePairs == ["a|b"])
    #expect(first.seen.version == "0.0.1")
    #expect(duplicateMessage(apps: ["a", "b"], seen: first.seen) == nil)
}

@Test func aNewAppInAKnownGroupIsToldAboutOnlyItsPairs() throws {
    let told = MessagesSeen(duplicatePairs: ["a|b"])
    let r = try #require(duplicateMessage(apps: ["a", "b", "c"], seen: told))
    #expect(r.show == .duplicateApps(apps: ["a", "b", "c"]))  // c pairs with both
    #expect(Set(r.seen.duplicatePairs ?? []) == ["a|b", "a|c", "b|c"])
    #expect(duplicateMessage(apps: ["a", "c"], seen: r.seen) == nil)
}

@Test func stoppedWarningsStayStopped() {
    #expect(duplicateMessage(apps: ["a", "b"], seen: MessagesSeen(duplicatesOff: true)) == nil)
}

@Test func oldMessagesFileStillReads() throws {
    let old = Data(#"{"version":"0.0.1","macOS":27}"#.utf8)
    let seen = try JSONDecoder().decode(MessagesSeen.self, from: old)
    #expect(seen == MessagesSeen(version: "0.0.1", macOS: 27))
}

@Test func namesJoinInPlainEnglish() {
    #expect(joinNames(["Calendar"]) == "Calendar")
    #expect(joinNames(["Calendar", "Fantastical"]) == "Calendar and Fantastical")
    #expect(joinNames(["A", "B", "C"]) == "A, B and C")
}
