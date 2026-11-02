import Foundation
import Testing
@testable import GzymsCore

private let m0 = 1_000_000.0  // a meeting at m0, 30 min long
private func meeting(_ id: String = "a", start: Double = m0) -> Meeting {
    Meeting(id: id, title: "standup", start: start, end: start + 1800, link: "https://meet.google.com/abc-defg-hij")
}

@Test func findsTheVideoLinkInUrlLocationOrNotes() {
    #expect(videoLink(url: nil, location: "https://meet.google.com/abc-defg-hij", notes: nil) == "https://meet.google.com/abc-defg-hij")
    #expect(videoLink(url: nil, location: "Room 4", notes: "Join Zoom Meeting\nhttps://acme.zoom.us/j/123456?pwd=x\nID: 123")
        == "https://acme.zoom.us/j/123456?pwd=x")
    let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0"
    #expect(videoLink(url: nil, location: nil, notes: "<\(teams)>") == teams)
    #expect(videoLink(url: nil, location: nil, notes: "Agenda: https://docs.google.com/doc then https://zoom.us/j/9") == "https://zoom.us/j/9")
    #expect(videoLink(url: nil, location: "https://zoom.us/pricing", notes: "lunch") == nil)
    #expect(videoLink(url: nil, location: nil, notes: nil) == nil)
    // Two links: the URL field wins over the notes.
    #expect(videoLink(url: "https://meet.google.com/x", location: nil, notes: "https://zoom.us/j/1") == "https://meet.google.com/x")
}

@Test func remindsAtEachPointAndNeverExpires() {
    let c = MeetingClock(points: [3, 0, -3])
    #expect(c.due([meeting()], now: m0 - 200) == nil)
    #expect(c.due([meeting()], now: m0 - 180)?.point == 3)
    #expect(c.due([meeting()], now: m0 - 10)?.point == 3)  // still up, nobody acted
    #expect(c.due([meeting()], now: m0 + 1)?.point == 0)
    #expect(c.due([meeting()], now: m0 + 200)?.point == -3)
    #expect(c.due([meeting()], now: m0 + 1800) == nil)  // the meeting ended
}

@Test func snoozeJumpsToTheNextPointAndTheLastOneEndsIt() {
    var c = MeetingClock(points: [3, 0, -3])
    c.snooze(meeting(), now: m0 - 170)
    #expect(c.due([meeting()], now: m0 - 60) == nil)
    #expect(c.due([meeting()], now: m0)?.point == 0)
    c.snooze(meeting(), now: m0 + 5)
    #expect(c.due([meeting()], now: m0 + 179) == nil)
    #expect(c.due([meeting()], now: m0 + 180)?.point == -3)
    c.snooze(meeting(), now: m0 + 200)
    #expect(c.due([meeting()], now: m0 + 600) == nil)
}

@Test func joinOrDismissEndsOnlyThatOccurrence() {
    var c = MeetingClock()
    c.finish("a")
    #expect(c.due([meeting()], now: m0) == nil)
    // Tomorrow's occurrence of the same event has its own id (event id + start).
    #expect(c.due([meeting("a+tomorrow", start: m0 + 86400)], now: m0 + 86400)?.point == 3)
}

@Test func onePointRemindsOnceAndSnoozeWalksTheLadder() {
    var c = MeetingClock(points: [5])
    #expect(c.due([meeting()], now: m0 - 300)?.point == 5)
    #expect(c.due([meeting()], now: m0 + 200)?.point == 5)  // stays up, no new point
    #expect(c.nextCheck([meeting()], now: m0 - 290) == nil)
    c.snooze(meeting(), now: m0 - 290)
    #expect(c.due([meeting()], now: m0 - 200) == nil)
    #expect(c.nextCheck([meeting()], now: m0 - 290) == m0 - 180)
    #expect(c.due([meeting()], now: m0 - 180)?.point == 3)
    c.snooze(meeting(), now: m0 - 170)
    #expect(c.due([meeting()], now: m0)?.point == 0)
    c.snooze(meeting(), now: m0 + 1)
    #expect(c.due([meeting()], now: m0 + 180)?.point == -3)
    c.snooze(meeting(), now: m0 + 181)  // last step: done
    #expect(c.due([meeting()], now: m0 + 600) == nil)
}

@Test func aMovedMeetingIsANewReminder() {
    var c = MeetingClock()
    c.finish("a@10:00")
    let moved = meeting("a@10:30", start: m0 + 1800)
    #expect(c.due([moved], now: m0 + 1800 - 180)?.point == 3)
}

@Test func twoMeetingsAtOnceShowOneAfterTheOther() {
    var c = MeetingClock()
    let early = meeting("early", start: m0), late = meeting("late", start: m0 + 60)
    #expect(c.due([late, early], now: m0)?.meeting.id == "early")
    c.finish("early")
    #expect(c.due([late, early], now: m0)?.meeting.id == "late")
}

@Test func wakingPastSeveralPointsShowsTheLastOnly() {
    let c = MeetingClock(points: [5, 3, 0, -3])
    #expect(c.due([meeting()], now: m0 + 120)?.point == 0)  // slept 9:50–10:02
}

@Test func joinedSnoozedAndDismissedSurviveARestart() throws {
    let a = meeting("evt@\(Int(m0))"), b = meeting("other@\(Int(m0))")
    var c = MeetingClock(points: [3, 0, -3])
    c.finish(a.id)
    c.snooze(b, now: m0 - 170)
    let data = try JSONEncoder().encode(c.saved(now: m0))
    var restarted = MeetingClock(points: [3, 0, -3])
    restarted.restore(try JSONDecoder().decode(MeetingClock.Saved.self, from: data))
    #expect(restarted.due([a], now: m0 + 180) == nil)  // 14:33 on 2026-11-02: joined, then the bar restarted
    #expect(restarted.due([b], now: m0 - 60) == nil)
    #expect(restarted.due([b], now: m0)?.point == 0)
}

@Test func savedDropsOccurrencesThatStartedOverADayAgo() {
    var c = MeetingClock()
    c.finish("old@\(Int(m0))")
    c.finish("new@\(Int(m0 + 86400))")
    #expect(c.saved(now: m0 + 86400 + 60).done == ["new@\(Int(m0 + 86400))"])
}

@Test func nextCheckIsTheNextPoint() {
    var c = MeetingClock(points: [3, 0, -3])
    #expect(c.nextCheck([meeting()], now: m0 - 600) == m0 - 180)
    #expect(c.nextCheck([meeting()], now: m0 - 180) == m0)
    c.finish("a")
    #expect(c.nextCheck([meeting()], now: m0 - 600) == nil)
}
