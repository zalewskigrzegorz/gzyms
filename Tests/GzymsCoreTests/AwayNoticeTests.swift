import Foundation
import Testing
@testable import GzymsCore

private let wall = Date(timeIntervalSince1970: 1_800_000_000)

@Test func theNoticeCountsTheMissedList() {
    #expect(awayNotice(missed: 0) == nil)
    #expect(awayNotice(missed: 1) == "1 notification while you were away")
    #expect(awayNotice(missed: 7) == "7 notifications while you were away")
    #expect(missedTitle(7) == "Missed while you were away · 7")
}

@Test func awayIsAQuietPeriod() {
    var s = NotificationStore()
    #expect(!s.quietPeriod)
    s.setAway(true, now: 0)
    #expect(s.quietPeriod)
    s.post(note("a"), now: 0)
    s.post(note("b", app: nil), now: 1)
    s.post(.pending(app: "com.app", at: wall), now: 2)
    #expect(s.banner == nil)
    #expect(s.missed.map(\.id) == ["b", "a"])  // newest first, the pending icon never filed
    #expect(s.count("com.app") == 0 && s.count(nil) == 0)  // the bar's counts leave them out
    s.setAway(false, now: 3)
    #expect(!s.quietPeriod && s.missed.count == 2)
    s.post(note("c"), now: 4)
    #expect(s.banner?.id == "c")
}

@Test func armageddonStillBreaksThroughALock() {
    var s = NotificationStore()
    s.setAway(true, now: 0)
    s.post(note("boom", level: .armageddon), now: 0)
    #expect(s.banner?.id == "boom")
    #expect(s.missed.isEmpty)
}

@Test func lockingFilesTheStackToItsList() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.setAway(true, now: 1)
    #expect(s.banner == nil)
    #expect(s.inbox("com.app").map(\.id) == ["a"])
    #expect(s.missed.isEmpty)
}

@Test func openedOrRemovedMissedIsGoneForGood() {
    var s = NotificationStore()
    s.setDND(.distantFuture, now: 0)
    for id in ["a", "b", "c"] { s.post(note(id), now: 0) }
    s.setDND(nil, now: 1)
    #expect(s.open("a")?.id == "a")
    s.remove("b", now: 2)
    #expect(s.missed.map(\.id) == ["c"])
    #expect(s.count("com.app") == 0)
    s.clearMissed()
    #expect(s.missed.isEmpty && s.count("com.app") == 0)
}

@Test func anUpdateStaysInTheMissedList() {
    var s = NotificationStore()
    s.setAway(true, now: 0)
    s.post(note("a", "old"), now: 0)
    s.setAway(false, now: 1)
    s.post(note("a", "new"), now: 2)
    #expect(s.banner == nil)
    #expect(s.missed.map(\.title) == ["new"])
}

@Test func bannerOffAppsGoToTheMissedListToo() {
    var s = NotificationStore()
    s.appRules = ["com.app": AppRule(banner: false)]
    s.setAway(true, now: 0)
    s.post(note("a"), now: 0)
    #expect(s.missed.map(\.id) == ["a"] && s.count("com.app") == 0)
}

@Test func theMissedListSurvivesARestartAndKeep() throws {
    var s = NotificationStore()
    s.setAway(true, now: 0)
    var old = note("old"), fresh = note("fresh")
    old.at = wall - 7200
    fresh.at = wall
    s.post(old, now: 0)
    s.post(fresh, now: 1)
    let saved = s.saved(now: 1, wall: wall)
    #expect(saved.rows.filter { $0.place == .missed }.map(\.id) == ["fresh", "old"])
    #expect(saved.text(now: wall).contains("Missed while you were away (2):"))
    var r = NotificationStore()
    r.restore(try JSONDecoder().decode(NotificationStore.Saved.self, from: JSONEncoder().encode(saved)), now: 0, wall: wall)
    #expect(r.missed.map(\.id) == ["fresh", "old"])
    r.keep = .hour
    #expect(r.prune(wall: wall) == 0)
    #expect(r.missed.map(\.id) == ["fresh", "old"])  // waits until read, whatever its age
    #expect(NotificationStore().saved(now: 0, wall: wall).missed == nil)  // an empty list writes nothing new
}
