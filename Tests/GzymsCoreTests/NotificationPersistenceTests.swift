import Foundation
import Testing
@testable import GzymsCore

private let wall = Date(timeIntervalSince1970: 1_800_000_000)

private func roundTrip(_ s: NotificationStore.Saved) throws -> NotificationStore.Saved {
    try JSONDecoder().decode(NotificationStore.Saved.self, from: JSONEncoder().encode(s))
}

@Test func inboxAndSnoozeSurviveRoundTrip() throws {
    var s = NotificationStore()
    s.post(note("a", app: "com.one"), now: 0)
    s.tick(now: 6)  // expires into its list
    s.post(note("b", app: "com.two"), now: 7)
    s.snooze(minutes: 3, now: 7)  // back at uptime 187
    var r = NotificationStore()
    // A reboot: uptime starts over, a minute of wall time went by.
    r.restore(try roundTrip(s.saved(now: 7, wall: wall)), now: 1000, wall: wall + 60)
    #expect(r.inbox("com.one").map(\.id) == ["a"])
    #expect(r.banner == nil)
    #expect(r.nextDeadline == 1120)
    r.tick(now: 1120)
    #expect(r.banner?.id == "b" && r.banner?.reminder == true)
}

@Test func overdueSnoozeComesBackAtOnce() throws {
    var s = NotificationStore()
    s.post(note("b"), now: 0)
    s.snooze(minutes: 3, now: 0)
    var r = NotificationStore()
    r.restore(try roundTrip(s.saved(now: 0, wall: wall)), now: 50, wall: wall + 600)
    r.tick(now: 50)
    #expect(r.banner?.id == "b")
}

@Test func stackIsFiledOnSave() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(note("b"), now: 1)
    var m = note("meeting-1", app: nil)
    m.meetingStart = 2_000_000_000
    s.post(m, now: 2)
    let saved = s.saved(now: 3, wall: wall)
    #expect(Set(saved.inbox.map(\.id)) == ["a", "b"])  // the calendar posts its meeting again
    #expect(saved.inbox.allSatisfy { !$0.reminder })
}

@Test func sameStoreGivesTheSameSnapshot() {
    var s = NotificationStore()
    for app in ["com.a", "com.b", "com.c", "com.d"] { s.post(note(app, app: app), now: 0); s.dismiss(now: 0); s.post(note("\(app).2", app: app), now: 0); s.tick(now: 6) }
    s.post(note("bell", app: nil), now: 7)
    s.tick(now: 13)
    #expect(s.saved(now: 13, wall: wall).inbox.map(\.id) == ["bell", "com.a.2", "com.b.2", "com.c.2", "com.d.2"])
}

@Test func pendingIconIsNotSaved() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: wall), now: 0)
    #expect(s.saved(now: 1, wall: wall).inbox.isEmpty)
}

@Test func inboxKeepsItsOrderPerApp() throws {
    var s = NotificationStore()
    for (i, id) in ["a", "b", "c"].enumerated() { s.post(note(id), now: Double(i) * 10); s.tick(now: Double(i) * 10 + 6) }
    var r = NotificationStore()
    r.restore(try roundTrip(s.saved(now: 30, wall: wall)), now: 0, wall: wall)
    #expect(r.inbox("com.app").map(\.id) == ["c", "b", "a"])
}

@Test func restoredInboxDedupsById() throws {
    var s = NotificationStore()
    s.post(note("x", "old"), now: 0)
    s.tick(now: 6)
    var r = NotificationStore()
    r.restore(try roundTrip(s.saved(now: 6, wall: wall)), now: 0, wall: wall)
    r.post(note("x", "new"), now: 1)
    #expect(r.inbox("com.app").map(\.title) == ["new"])
    #expect(r.banner == nil)
}

@Test func loadMissingFileIsEmpty() {
    var logged: [String] = []
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("gzyms-missing-\(UUID()).json")
    #expect(NotificationStore.load(url) { logged.append($0) } == nil)
    #expect(logged.isEmpty)
}

@Test func brokenFileIsMovedAside() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gzyms-broken-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("notifications.json")
    try Data("{".utf8).write(to: url)
    var logged: [String] = []
    #expect(NotificationStore.load(url) { logged.append($0) } == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("notifications.json.broken-") })
    #expect(logged.count == 1)
}

@Test func savedFileLoadsBack() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("gzyms-ok-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    let saved = s.saved(now: 0, wall: wall)
    try JSONEncoder().encode(saved).write(to: url, options: .atomic)
    #expect(NotificationStore.load(url) { _ in } == saved)
}
