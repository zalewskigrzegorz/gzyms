import Foundation
import Testing
@testable import GzymsCore

private let wall = Date(timeIntervalSince1970: 1_800_000_000)

private func meeting(_ id: String) -> GzymsNotification {
    var m = note(id, app: nil)
    m.meetingStart = 2_000_000_000
    return m
}

@Test func dndSendsToTheMissedListInsteadOfStacking() {
    var s = NotificationStore()
    s.setDND(.distantFuture, now: 0)
    s.post(note("a"), now: 0)
    s.post(note("c", level: .critical), now: 1)
    s.post(.pending(app: "com.app", at: wall), now: 2)
    #expect(s.banner == nil)
    #expect(s.missed.map(\.id) == ["c", "a"])
    #expect(s.count("com.app") == 0)
}

@Test func armageddonAndMeetingBreakDNDByDefault() {
    var s = NotificationStore()
    s.setDND(.distantFuture, now: 0)
    s.post(meeting("meeting-1"), now: 0)
    s.post(note("boom", level: .armageddon), now: 1)
    #expect(Set(s.stacked.map(\.id)) == ["meeting-1", "boom"])
}

@Test func whatBreaksThroughIsConfigurable() {
    var s = NotificationStore()
    s.breaksThrough = [.critical]
    s.setDND(.distantFuture, now: 0)
    s.post(note("boom", level: .armageddon), now: 0)
    s.post(meeting("meeting-1"), now: 1)
    s.post(note("c", level: .critical), now: 2)
    #expect(s.stacked.map(\.id) == ["c"])
    #expect(s.quiet(note("boom", level: .armageddon)))
}

@Test func turningDNDOnFilesTheStack() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(note("b"), now: 1)
    s.post(meeting("meeting-1"), now: 2)
    s.setDND(.distantFuture, now: 3)
    #expect(s.stacked.map(\.id) == ["meeting-1"])
    #expect(Set(s.inbox("com.app").map(\.id)) == ["a", "b"])
}

@Test func turningDNDOffReplaysNothing() {
    var s = NotificationStore()
    s.setDND(.distantFuture, now: 0)
    s.post(note("a"), now: 0)
    s.setDND(nil, now: 1)
    #expect(s.banner == nil && s.missed.count == 1)
    s.post(note("b"), now: 2)
    #expect(s.banner?.id == "b")
}

@Test func snoozeBackInDNDGoesToTheMissedList() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.snooze(minutes: 1, now: 0)
    s.setDND(.distantFuture, now: 1)
    s.tick(now: 60)
    #expect(s.banner == nil)
    #expect(s.missed.map(\.id) == ["a"])
    #expect(s.missed.first?.reminder == false)
}

@Test func dndStillArmsThePhone() {
    var s = NotificationStore()
    s.phone.url = "https://ntfy.sh/x"
    s.phone.after = 10
    s.setDND(.distantFuture, now: 0)
    s.post(note("c", level: .critical), now: 0)
    #expect(s.tick(now: 10).map(\.id) == ["c"])
}

@Test func dndSurvivesARestartUntilItsTime() throws {
    var s = NotificationStore()
    s.setDND(wall + 3600, now: 0)
    let data = try JSONEncoder().encode(s.saved(now: 0, wall: wall))
    var r = NotificationStore()
    r.restore(try JSONDecoder().decode(NotificationStore.Saved.self, from: data), now: 0, wall: wall + 60)
    #expect(r.dnd == wall + 3600)
    var late = NotificationStore()
    late.restore(try JSONDecoder().decode(NotificationStore.Saved.self, from: data), now: 0, wall: wall + 7200)
    #expect(late.dnd == nil)
}

@Test func untilTomorrowIsTheNextEightOClock() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(identifier: "Europe/Warsaw"))
    let late = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30)))
    let early = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 7)))
    let eight = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8)))
    #expect(dndUntilMorning(now: late, calendar: cal) == eight)
    #expect(dndUntilMorning(now: early, calendar: cal) == eight)
}

@Test func dndCommandTakesOnMinutesOrOff() {
    #expect(dndMessage(["on"]) == "on")
    #expect(dndMessage(["on", "30"]) == "on:30")
    #expect(dndMessage(["off"]) == "off")
    for bad in [[], ["on", "0"], ["on", "x"], ["off", "5"], ["maybe"]] { #expect(dndMessage(bad) == nil) }
    #expect(dndUntil("on:30", now: wall) == .some(wall + 1800))
    #expect(dndUntil("on", now: wall) == .some(.distantFuture))
    #expect(dndUntil("off", now: wall) == .some(nil))
    #expect(dndUntil("on:-1", now: wall) == nil)
}

@Test func dndBreaksThroughIsRead() {
    let ok = loadConfig(toml: "[dnd]\nbreaks_through = [\"critical\"]\n")
    #expect(ok.config.dndBreaks == [.critical])
    #expect(ok.problems.isEmpty)
    let bad = loadConfig(toml: "[dnd]\nbreaks_through = [\"loud\"]\n")
    #expect(bad.config.dndBreaks == [.armageddon, .meetings])
    #expect(bad.problems.contains { $0.hasPrefix("dnd.breaks_through") })
    #expect(GzymsConfig.defaults.dndBreaks == [.armageddon, .meetings])
}

@Test func sharingFilesEverythingQuietly() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(meeting("meeting-1"), now: 1)
    s.setSharing(true, now: 2)
    #expect(s.banner == nil)
    s.post(note("boom", level: .armageddon), now: 3)
    #expect(s.banner == nil && s.takeSounds().map(\.id) == ["a", "meeting-1"])
    #expect(s.inbox("com.app").map(\.id) == ["a"])  // on screen when sharing began
    #expect(s.missed.map(\.id) == ["boom"])
    s.setSharing(false, now: 4)
    #expect(s.banner == nil)
    s.post(note("b"), now: 5)
    #expect(s.banner?.id == "b")
}
