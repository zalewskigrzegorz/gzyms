import Foundation
import Testing
@testable import GzymsCore

/// Greg: a full stack beeped for new notifications, and after clearing it they never came up.
@Test func fullStackLetsTheWaitingOnesInWhenRoomFrees() {
    var s = NotificationStore()
    for (i, id) in ["a", "b", "c", "d", "e", "f"].enumerated() { s.post(note(id, level: .critical), now: Double(i)) }
    var shown: [String] = []
    while let b = s.banner { shown.append(b.id); s.dismiss(now: 10) }
    #expect(shown == ["a", "b", "c", "d", "e", "f"])
    #expect(s.count("com.app") == 0)
}

@Test func theWaitingOnesShowInTheListAtOnce() {
    var s = NotificationStore()
    for i in 0..<6 { s.post(note("n\(i)"), now: Double(i) / 10) }
    #expect(s.stacked.map(\.id) == ["n0", "n1", "n2", "n3"])
    #expect(s.inbox("com.app").map(\.id) == ["n5", "n4"])
    s.dismiss(now: 1)
    #expect(s.stacked.map(\.id) == ["n1", "n2", "n3", "n4"])
    #expect(s.inbox("com.app").map(\.id) == ["n5"])
}

@Test func soundPlaysWhenItEntersTheStackNotWhileItWaits() {
    var s = NotificationStore()
    for i in 0..<5 { s.post(note("n\(i)"), now: Double(i) / 10) }
    #expect(s.takeSounds().map(\.id) == ["n0", "n1", "n2", "n3"])
    s.dismiss(now: 1)
    #expect(s.takeSounds().map(\.id) == ["n4"])
    s.tick(now: 100)  // the banner runs out: nothing new comes in
    #expect(s.takeSounds().isEmpty)
}

@Test func priorityOnesSoundAtOnceAndOnlyOnce() {
    var s = NotificationStore()
    for i in 0..<4 { s.post(note("c\(i)", level: .critical), now: Double(i)) }
    _ = s.takeSounds()
    s.post(note("late", level: .critical), now: 5)
    #expect(s.takeSounds().map(\.id) == ["late"])
    #expect(!s.contains("late"))
    s.dismiss(now: 6)
    #expect(s.contains("late"))
    #expect(s.takeSounds().isEmpty)
}

@Test func priorityIsConfigurable() {
    var s = NotificationStore()
    s.priority = []
    for i in 0..<5 { s.post(note("c\(i)", level: .critical), now: Double(i)) }
    #expect(s.takeSounds().map(\.id) == ["c0", "c1", "c2", "c3"])
}

@Test func onePushedBackByAnArmageddonDoesNotSoundTwice() {
    var s = NotificationStore()
    for i in 0..<4 { s.post(note("n\(i)"), now: Double(i) / 10) }
    _ = s.takeSounds()
    s.post(note("boom", level: .armageddon), now: 1)
    #expect(s.takeSounds().map(\.id) == ["boom"])
    #expect(s.inbox("com.app").map(\.id) == ["n3"])
    s.dismiss(now: 2)  // boom leaves, n3 comes back
    #expect(s.contains("n3"))
    #expect(s.takeSounds().isEmpty)
}

@Test func clearingTheListDropsTheWaitingOnes() {
    var s = NotificationStore()
    for i in 0..<6 { s.post(note("n\(i)"), now: Double(i) / 10) }
    s.clearAll("com.app")
    var shown: [String] = []
    while let b = s.banner { shown.append(b.id); s.dismiss(now: 10) }
    #expect(shown == ["n0", "n1", "n2", "n3"])
}

@Test func theLineSurvivesARestartInOrder() throws {
    var s = NotificationStore()
    for i in 0..<6 { s.post(note("n\(i)", level: .error), now: Double(i) / 10) }
    s.next(now: 1)  // n1 on screen: it comes back first
    _ = s.takeSounds()
    let data = try JSONEncoder().encode(s.saved(now: 1, wall: Date(timeIntervalSince1970: 0)))
    var r = NotificationStore()
    r.restore(try JSONDecoder().decode(NotificationStore.Saved.self, from: data), now: 0, wall: Date(timeIntervalSince1970: 60))
    #expect(r.stacked.map(\.id) == ["n1", "n2", "n3", "n0"])
    #expect(r.inbox("com.app").map(\.id).sorted() == ["n4", "n5"])
    #expect(r.takeSounds().isEmpty)  // these sounded before the restart
    r.dismiss(now: 1)
    #expect(r.takeSounds().map(\.id) == ["n4"])
}

@Test func aFileFromBeforeTheQueueStillLoads() throws {
    let old = #"{"inbox":[],"snoozed":[]}"#
    let s = try JSONDecoder().decode(NotificationStore.Saved.self, from: Data(old.utf8))
    #expect(s.queued == nil)
}

@Test func anUpdateWhileWaitingComesUpWithTheNewText() {
    var s = NotificationStore()
    for i in 0..<5 { s.post(note("n\(i)"), now: Double(i) / 10) }
    s.post(note("n4", "new"), now: 1)
    s.dismiss(now: 2)
    #expect(s.stacked.last?.title == "new")
}
