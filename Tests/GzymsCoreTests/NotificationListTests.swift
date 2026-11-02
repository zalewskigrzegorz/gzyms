import Foundation
import Testing
@testable import GzymsCore

private let wall = Date(timeIntervalSince1970: 1_800_000_000)

private func roundTrip(_ s: NotificationStore.Saved) throws -> NotificationStore.Saved {
    try JSONDecoder().decode(NotificationStore.Saved.self, from: JSONEncoder().encode(s))
}

/// Six in: four in the stack (one on screen), two waiting for room, one in a list, one snoozed, and a meeting.
private func busyStore() -> NotificationStore {
    var s = NotificationStore()
    s.post(note("old", app: "com.list"), now: 0)
    s.tick(now: 6)  // expires into its list
    s.post(note("later", app: "com.snooze"), now: 7)
    s.snooze(minutes: 5, now: 7)
    var m = note("meeting-1", "Standup", app: nil)
    m.meetingStart = 2_000_000_000
    s.post(m, now: 8)
    for id in ["a", "b", "c", "d", "e"] { s.post(note(id), now: 9) }
    return s
}

@Test func rowsSayWhereEachOneIs() throws {
    let rows = try roundTrip(busyStore().saved(now: 10, wall: wall)).rows
    let place = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, "\($0.place.rawValue)\($0.position.map(String.init) ?? "")") })
    #expect(place == ["meeting-1": "stack1", "a": "stack2", "b": "stack3", "c": "stack4", "d": "waiting1", "e": "waiting2",
                      "old": "list", "later": "snoozed1"])
    #expect(rows.first { $0.id == "meeting-1" }?.source == "meeting")
    #expect(rows.first { $0.id == "old" }?.source == "com.list")
    #expect(rows.first { $0.id == "a" }?.heard == true)
    #expect(rows.first { $0.id == "d" }?.heard == false, "an info that went straight to waiting has not sounded")
}

@Test func liveIsNotRestored() throws {
    var r = NotificationStore()
    r.restore(try roundTrip(busyStore().saved(now: 10, wall: wall)), now: 0, wall: wall)
    #expect(r.stacked.allSatisfy { $0.meetingStart == nil }, "the calendar brings its meeting back")
}

@Test func waitingOneClearedFromItsListIsGone() {
    var s = busyStore()
    s.clearAll("com.app")
    #expect(s.saved(now: 10, wall: wall).rows.filter { $0.place == .waiting }.isEmpty)
}

@Test func fileWithoutLiveListsEverything() throws {
    var saved = busyStore().saved(now: 10, wall: wall)
    saved.live = nil  // written by a bar from before this field
    #expect(try roundTrip(saved).rows.allSatisfy { $0.place == .list || $0.place == .snoozed })
}

@Test func removeTakesASnoozedOneToo() {
    var s = busyStore()
    s.remove("later", now: 10)
    #expect(!s.saved(now: 10, wall: wall).rows.contains { $0.id == "later" })
}

@Test func jsonHasTheWholeText() throws {
    var s = NotificationStore()
    var n = note("x", String(repeating: "long ", count: 30), app: "com.app")
    n.body = "line one\nline two"
    s.post(n, now: 0)
    let obj = try JSONSerialization.jsonObject(with: s.saved(now: 0, wall: wall).json()) as? [String: Any]
    let row = (obj?["notifications"] as? [[String: Any]])?.first
    #expect(row?["title"] as? String == n.title)
    #expect(row?["body"] as? String == "line one\nline two")
    #expect(row?["place"] as? String == "stack" && row?["position"] as? Int == 1)
    #expect(row?["at"] as? String == "1970-01-01T00:00:00Z")
}

@Test func textIsGroupedAndCut() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var s = NotificationStore()
    var n = note("x", String(repeating: "a", count: 100), app: "com.app", level: .error)
    n.body = "two\nlines"
    s.post(n, now: 0)
    let text = s.saved(now: 0, wall: wall).text(now: Date(timeIntervalSince1970: 60), calendar: cal)
    #expect(text == "Stack, 1 is on screen (1):\n  1  error      00:00  com.app  \(String(repeating: "a", count: 69))…  [x]  heard\n")
    #expect(NotificationStore.Saved.empty.text(now: wall) == "No notifications.\n")
}
