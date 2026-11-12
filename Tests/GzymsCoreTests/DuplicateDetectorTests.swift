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

@Test func remindersAboutOneMeetingFromTwoAppsMatchMinutesApartInOtherWords() {
    // The real 15:00 case: Spark's "📅 Bartek:Greg", then Calendar and Notion Calendar with their own text.
    var d = DuplicateDetector()
    let m = ["Bartek:Greg"]
    #expect(d.record(app: "com.readdle.SparkDesktop", title: "📅 Bartek:Greg", body: nil, meetings: m, at: 0) == nil)
    #expect(d.record(app: "com.apple.iCal", title: "Bartek:Greg", body: "15:00–15:30", meetings: m, at: 7)?.apps
            == ["com.apple.iCal", "com.readdle.SparkDesktop"])
    #expect(d.record(app: "com.cron.electron", title: "Bartek:Greg", body: "in 5 min", meetings: m, at: 300)?.apps.count == 3)
    #expect(d.record(app: "com.apple.iCal", title: "Bartek:Greg", body: "now", meetings: m, at: 600) == nil)  // its own next alert
}

@Test func aMeetingWordInAChatMessageBodyIsNotAReminder() {
    var d = DuplicateDetector()
    _ = d.record(app: "com.apple.iCal", title: "Sync", body: nil, meetings: ["Sync"], at: 0)
    #expect(d.record(app: "com.tinyspeck.slackmacgap", title: "Anna", body: "sync now?", meetings: ["Sync"], at: 60) == nil)
}

@Test func meetingRemindersOutsideTheirWindowDoNotMatch() {
    var d = DuplicateDetector()
    _ = d.record(app: "a", title: "Bartek:Greg", body: nil, meetings: ["Bartek:Greg"], at: 0)
    #expect(d.record(app: "b", title: "Bartek:Greg", body: nil, meetings: ["Bartek:Greg"], at: DuplicateDetector.meetingWindow + 1) == nil)
}

@Test func pairsAreSortedAndUnique() {
    #expect(appPairs(["b", "a", "b"]) == ["a|b"])
    #expect(appPairs(["c", "a", "b"]) == ["a|b", "a|c", "b|c"])
    #expect(appPairs(["a"]).isEmpty)
}

private let seenAt = Date(timeIntervalSince1970: 1_000)

@Test func aPairIsToldOnceInEitherOrder() {
    let first = recordDuplicates(apps: ["b", "a"], at: seenAt, seen: MessagesSeen(version: "0.0.1"))
    #expect(first.tell == ["a", "b"])
    #expect(first.seen.duplicatePairs == ["a|b"])
    #expect(first.seen.version == "0.0.1")
    #expect(recordDuplicates(apps: ["a", "b"], at: seenAt, seen: first.seen).tell.isEmpty)
}

@Test func aNewAppInAKnownGroupIsToldAboutOnlyItsPairs() {
    let r = recordDuplicates(apps: ["a", "b", "c"], at: seenAt, seen: MessagesSeen(duplicatePairs: ["a|b"]))
    #expect(r.tell == ["a", "b", "c"])  // c pairs with both
    #expect(Set(r.seen.duplicatePairs ?? []) == ["a|b", "a|c", "b|c"])
    #expect(recordDuplicates(apps: ["a", "c"], at: seenAt, seen: r.seen).tell.isEmpty)
}

@Test func stoppedWarningsStayStoppedButTheListStillGrows() {
    let r = recordDuplicates(apps: ["a", "b"], at: seenAt, seen: MessagesSeen(duplicatesOff: true))
    #expect(r.tell.isEmpty)
    #expect(r.seen.duplicatePairs == nil)
    #expect(r.seen.duplicateGroups == [DuplicateGroup(apps: ["a", "b"], count: 1, last: seenAt)])
}

@Test func theListCountsEachGroupAndKeepsTheLastTime() {
    var seen = MessagesSeen()
    seen = recordDuplicates(apps: ["b", "a"], at: seenAt, seen: seen).seen
    seen = recordDuplicates(apps: ["a", "b"], at: seenAt + 60, seen: seen).seen
    seen = recordDuplicates(apps: ["a", "b", "c"], at: seenAt + 90, seen: seen).seen
    #expect(seen.duplicateGroups == [DuplicateGroup(apps: ["a", "b"], count: 2, last: seenAt + 60),
                                     DuplicateGroup(apps: ["a", "b", "c"], count: 1, last: seenAt + 90)])
}

@Test func forgettingAGroupTellsItsPairsAgain() {
    var seen = recordDuplicates(apps: ["a", "b"], at: seenAt, seen: MessagesSeen(duplicatesOff: nil)).seen
    seen = recordDuplicates(apps: ["c", "d"], at: seenAt, seen: seen).seen
    let after = seen.forgetting(group: ["a", "b"])
    #expect(after.duplicateGroups == [DuplicateGroup(apps: ["c", "d"], count: 1, last: seenAt)])
    #expect(after.duplicatePairs == ["c|d"])
    #expect(recordDuplicates(apps: ["a", "b"], at: seenAt, seen: after).tell == ["a", "b"])
}

@Test func theNoticeNamesTheAppsAndPointsToDebug() {
    let n = duplicateNotice(names: ["Calendar", "Spark Desktop"])
    #expect(n.title == "Apps send the same notification")
    #expect(n.body == "Calendar and Spark Desktop. See Debug.")
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
