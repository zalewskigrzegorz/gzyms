import Foundation
import Testing
@testable import GzymsCore

func note(_ id: String, _ title: String = "t", app: String? = "com.app", level: NotifyLevel = .info) -> GzymsNotification {
    GzymsNotification(id: id, app: app, level: level, title: title, subtitle: nil, body: nil, link: nil, altLink: nil, sound: nil,
                      at: Date(timeIntervalSince1970: 0))
}

@Test func infoExpiresAfterSixSeconds() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.tick(now: 5.9)
    #expect(s.banner?.id == "a")
    s.tick(now: 6)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 1)
}

@Test func levelsHaveTheirTimes() {
    #expect(NotifyLevel.allCases.map(\.seconds) == [6, 8, 12, nil, nil])
}

@Test func criticalStaysUntilActedOn() {
    var s = NotificationStore()
    s.post(note("a", level: .critical), now: 0)
    s.tick(now: 600)
    #expect(s.banner?.id == "a")
    #expect(s.remaining(now: 600) == nil)
    #expect(s.nextDeadline == nil)
}

@Test func equalLevelWaits() {
    var s = NotificationStore()
    s.post(note("a", "first"), now: 0)
    s.post(note("b", "second"), now: 1)
    #expect(s.banner?.title == "first")
    #expect(s.waiting == 1)
    #expect(s.count("com.app") == 0)
}

@Test func burstKeepsTheFirstOnScreenAndTheLastThreeWaiting() {
    var s = NotificationStore()
    for i in 0..<20 { s.post(note("n\(i)", "\(i)"), now: Double(i) / 20) }
    #expect(s.banner?.title == "0")
    #expect(s.waiting == 3)
    #expect(s.count("com.app") == 16)
    #expect(s.inbox("com.app").first?.id == "n16")
}

@Test func sameIdUpdatesBanner() {
    var s = NotificationStore()
    s.post(note("x", "A"), now: 0)
    s.post(note("x", "B"), now: 1)
    #expect(s.banner?.title == "B")
    #expect(s.count("com.app") == 0)
}

@Test func sameIdUpdatesInboxEntry() {
    var s = NotificationStore()
    s.post(note("x", "A"), now: 0)
    s.tick(now: 6)
    s.post(note("y", "other"), now: 7)
    s.post(note("x", "B"), now: 8)  // x is in the inbox: update it there, keep y on screen
    #expect(s.banner?.id == "y")
    #expect(s.inbox("com.app").map(\.title) == ["B"])
}

@Test func hoverPausesCountdown() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.hover(true, now: 2)
    s.tick(now: 10)
    #expect(s.banner != nil)
    s.hover(false, now: 10)
    s.tick(now: 13.9)
    #expect(s.banner != nil)
    s.tick(now: 14)
    #expect(s.banner == nil)
}

/// Every banner left alone until it expires, one after another: they go to their inboxes.
private func ignoreAll(_ s: inout NotificationStore) {
    while s.banner != nil, let d = s.nextDeadline { _ = s.tick(now: d) }
}

@Test func dismissForgetsIt() {
    // x means "done, nothing to do with it" (Greg): not in the list under the app's icon.
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.dismiss(now: 1)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 0)
}

@Test func ignoredGoesToInbox() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    ignoreAll(&s)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 1)
}

@Test func snoozeComesBackAsReminder() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.snooze(minutes: 3, now: 0)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 0)
    #expect(s.nextDeadline == 180)
    s.tick(now: 179)
    #expect(s.banner == nil)
    s.tick(now: 180)
    #expect(s.banner?.id == "a")
    #expect(s.banner?.reminder == true)
    // A reminder stays until acted on: missing it a second time would defeat the snooze.
    s.tick(now: 10_000)
    #expect(s.banner?.id == "a")
    #expect(s.remaining(now: 10_000) == nil)
}

@Test func openRemovesOnlyThatOne() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(note("b"), now: 1)
    s.post(note("c"), now: 2)
    _ = s.tick(now: 6)  // a expires to its inbox, b comes up
    #expect(s.open("a")?.id == "a")
    #expect(s.banner?.id == "b")
    #expect(s.open("c")?.id == "c")  // waiting: taken out of the stack
    #expect(s.waiting == 0)
    #expect(s.open("b")?.id == "b")
    #expect(s.banner == nil)
}

@Test func clearAllEmptiesOneApp() {
    var s = NotificationStore()
    s.post(note("a", app: "one"), now: 0)
    s.post(note("b", app: "two"), now: 1)
    s.post(note("c", app: "one"), now: 2)
    ignoreAll(&s)
    s.clearAll("one")
    #expect(s.count("one") == 0)
    #expect(s.count("two") == 1)
}

@Test func noAppGoesToBell() {
    var s = NotificationStore()
    s.post(note("a", app: nil), now: 0)
    ignoreAll(&s)
    #expect(s.count(nil) == 1)
}

@Test func inboxIsNewestFirst() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(note("b"), now: 1)
    s.post(note("c"), now: 2)
    ignoreAll(&s)
    #expect(s.inbox("com.app").map(\.id) == ["c", "b", "a"])
}

@Test func bellTakesNoAppAndAppsOffTheBar() {
    var s = NotificationStore()
    for (i, (id, app)) in [("a", nil), ("b", "com.slack"), ("c", "com.daemon")].enumerated() {
        var n = note(id, app: app)
        n.at = Date(timeIntervalSince1970: Double(i))
        s.post(n, now: Double(i))
    }
    ignoreAll(&s)
    let bell = bellInbox(s.inboxes, onBar: ["com.slack"])
    #expect(bell.map(\.id) == ["c", "a"])
}

@Test func badgeTextCapsAtNinePlus() {
    #expect(badgeText(1) == "1")
    #expect(badgeText(9) == "9")
    #expect(badgeText(10) == "9+")
}

@Test func pendingIsReplacedByItsRowNotFiled() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    #expect(s.banner?.compact == true)
    s.post(note("nc-1"), now: 5)
    #expect(s.banner?.id == "nc-1")
    #expect(s.count("com.app") == 0)
}

@Test func pendingExpiresSilently() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    s.tick(now: 9.9)
    #expect(s.banner != nil)
    s.tick(now: 10)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 0)
}

@Test func pendingDismissAndSnoozeLeaveNothing() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    s.snooze(minutes: 3, now: 1)
    s.dismiss(now: 1)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 0)
    #expect(s.nextDeadline == nil)
}

@Test func dismissedPendingFilesItsRowQuietly() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    s.dismiss(now: 1)
    s.post(note("nc-1"), now: 5)
    #expect(s.banner == nil)
    #expect(s.inbox("com.app").map(\.id) == ["nc-1"])
    s.post(note("nc-2"), now: 6)  // only the one row: the next message shows again
    #expect(s.banner?.id == "nc-2")
}

@Test func quietEndsAfterFifteenSeconds() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    s.dismiss(now: 1)
    s.post(note("nc-1"), now: 17)
    #expect(s.banner?.id == "nc-1")
}

@Test func openedPendingAlsoQuietsItsRow() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    _ = s.open("pending-com.app", now: 1)
    s.post(note("nc-1"), now: 5)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 1)
}

@Test func expiredPendingDoesNotQuietALateRow() {
    var s = NotificationStore()
    s.post(.pending(app: "com.app", at: Date(timeIntervalSince1970: 0)), now: 0)
    s.tick(now: 10)
    s.post(note("nc-1"), now: 12)
    #expect(s.banner?.id == "nc-1")
}

@Test func levelTimesComeFromTheConfig() {
    var s = NotificationStore()
    s.levelSeconds[.info] = 30
    s.post(note("a"), now: 0)
    s.tick(now: 29)
    #expect(s.banner?.id == "a")
    s.tick(now: 30)
    #expect(s.banner == nil)
    s.levelSeconds[.info] = .some(nil)
    s.post(note("b"), now: 40)
    #expect(s.nextDeadline == nil)
}

@Test func appWithBannerOffGoesStraightToItsCount() {
    var s = NotificationStore()
    s.appRules["com.app"] = AppRule(banner: false)
    s.post(note("a"), now: 0)
    #expect(s.banner == nil)
    #expect(s.count("com.app") == 1)
    s.post(note("a", "updated"), now: 1)
    #expect(s.inbox("com.app").map(\.title) == ["updated"])
    s.post(note("c", level: .critical), now: 2)
    #expect(s.banner?.id == "c")  // a critical one still shows
}

@Test func appLevelRaisesNeverLowers() {
    var s = NotificationStore()
    s.appRules["com.app"] = AppRule(banner: false, level: .armageddon)
    s.post(note("a"), now: 0)
    #expect(s.banner?.level == .armageddon)
    #expect(s.nextDeadline == nil)
    #expect(AppRule(level: .critical).raise(.armageddon) == .armageddon)
    #expect(AppRule(level: .critical).raise(.info) == .critical)
    #expect(AppRule().raise(.warning) == .warning)
}

@Test func aMeetingReminderNeverExpires() {
    var s = NotificationStore()
    var n = note("meeting-a")
    n.meetingStart = 1000
    s.post(n, now: 0)
    #expect(s.nextDeadline == nil)
    s.tick(now: 3600)
    #expect(s.banner?.id == "meeting-a")
}

// MARK: - The stack (M3c)

private func meeting(_ id: String) -> GzymsNotification {
    var n = note(id)
    n.meetingStart = 10_000
    return n
}

@Test func higherLevelPreempts() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(note("b", level: .error), now: 1)
    #expect(s.banner?.id == "b")
    #expect(s.waiting == 1)
    #expect(s.count("com.app") == 0)
}

@Test func preemptedComesBackWithItsTimeLeft() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)                  // info, 6 s
    s.post(note("b", level: .error), now: 2)   // a frozen with 4 s left
    s.tick(now: 14)                            // b expires after 12 s, a comes up
    #expect(s.banner?.id == "a")
    #expect(s.remaining(now: 14) == 4)
    s.tick(now: 18)
    #expect(s.banner == nil)
}

@Test func waitingHasNoClockUntilShown() {
    var s = NotificationStore()
    s.post(note("a", level: .error), now: 0)   // 12 s
    s.post(note("b"), now: 1)                  // waits, 6 s once shown
    s.tick(now: 12)
    #expect(s.banner?.id == "b")
    #expect(s.remaining(now: 12) == 6)
    #expect(s.nextDeadline == 18)
}

@Test func limitThreeFilesTheLowestOldest() {
    var s = NotificationStore()
    s.post(note("top", level: .critical), now: 0)
    s.post(note("w1", level: .warning), now: 1)
    s.post(note("i1"), now: 2)
    s.post(note("i2"), now: 3)
    s.post(note("w2", level: .warning), now: 4)  // fourth waiting: the oldest info goes
    #expect(s.waiting == 3)
    #expect(s.inbox("com.app").map(\.id) == ["i1"])
    #expect(s.banner?.id == "top")
}

@Test func meetingIsNotPushedOutByLower() {
    var s = NotificationStore()
    s.post(note("c", level: .critical), now: 0)
    s.post(meeting("meeting-m"), now: 1)
    for i in 0..<5 { s.post(note("e\(i)", level: .error), now: 2 + Double(i)) }
    #expect(s.contains("meeting-m"))
    #expect(s.waiting == 3)
}

@Test func sameIdUpdatesWaiting() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(meeting("meeting-m"), now: 1)  // preempts a
    s.post(note("a", "updated"), now: 2)
    #expect(s.banner?.id == "meeting-m")
    #expect(s.waiting == 1)
    s.dismiss(now: 3)
    #expect(s.banner?.title == "updated")
}

@Test func pendingNeverJoinsTheStack() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(.pending(app: "com.other", at: Date(timeIntervalSince1970: 0)), now: 1)
    #expect(s.banner?.id == "a")
    #expect(s.waiting == 0)
    s.dismiss(now: 2)
    s.post(.pending(app: "com.other", at: Date(timeIntervalSince1970: 0)), now: 3)
    s.post(note("b", level: .warning), now: 4)
    #expect(s.banner?.id == "b")
    #expect(s.waiting == 0)
    #expect(s.count("com.other") == 0)
}

@Test func nextAndPreviousWrapAndFreezeTime() {
    var s = NotificationStore()
    s.post(note("a", level: .error), now: 0)
    s.post(note("b"), now: 0)
    s.post(note("c"), now: 0)
    s.next(now: 2)  // a frozen with 10 s
    #expect(s.banner?.id == "b")
    #expect(s.remaining(now: 2) == 6)
    s.next(now: 3)
    #expect(s.banner?.id == "c")
    s.next(now: 4)  // wraps
    #expect(s.banner?.id == "a")
    #expect(s.remaining(now: 4) == 10)
    s.previous(now: 5)
    #expect(s.banner?.id == "c")
    #expect(s.waiting == 2)
}

@Test func nextWithOneBannerDoesNothing() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.next(now: 1)
    #expect(s.banner?.id == "a")
    #expect(s.remaining(now: 1) == 5)
}

@Test func switchKeepsThePause() {
    var s = NotificationStore()
    s.post(note("a"), now: 0)
    s.post(note("b"), now: 0)
    s.hover(true, now: 1)
    s.next(now: 2)
    #expect(s.isPaused)
    s.tick(now: 100)
    #expect(s.banner?.id == "b")
    s.hover(false, now: 100)
    #expect(s.remaining(now: 100) == 6)
    s.previous(now: 101)
    #expect(s.remaining(now: 101) == 5)  // a kept the 5 s it had under the pointer
}

@Test func afterActionTheHighestComesUp() {
    var s = NotificationStore()
    s.post(note("e", level: .error), now: 0)
    s.post(note("i"), now: 0)
    s.post(note("w", level: .warning), now: 0)
    s.next(now: 1)  // w is next by rank
    #expect(s.banner?.id == "w")
    s.dismiss(now: 2)
    #expect(s.banner?.id == "e")
}

@Test func reminderWaitsUnderArmageddon() {
    var s = NotificationStore()
    s.post(note("r"), now: 0)
    s.snooze(minutes: 3, now: 0)
    s.post(note("boom", level: .armageddon), now: 1)
    s.tick(now: 180)
    #expect(s.banner?.id == "boom")
    #expect(s.waiting == 1)
    s.next(now: 181)  // frozen until the click
    #expect(s.banner?.id == "boom")
    _ = s.open("boom", now: 182)
    #expect(s.banner?.id == "r")
    #expect(s.banner?.reminder == true)
}

@Test func removeTakesAWaitingOne() {
    var s = NotificationStore()
    s.post(note("c", level: .critical), now: 0)
    s.post(meeting("meeting-m"), now: 1)
    s.remove("meeting-m", now: 2)
    #expect(!s.contains("meeting-m"))
    #expect(s.waiting == 0)
}

@Test func waitingCountsForThePhoneFromArrival() {
    var s = NotificationStore()
    s.phone.url = "https://ntfy.sh/x"
    s.phone.after = 60
    s.post(note("c1", level: .critical), now: 0)
    s.post(note("c2", level: .critical), now: 1)  // waits, still goes out after 60 s
    #expect(s.tick(now: 61).map(\.id) == ["c1", "c2"])
}

@Test func higherLevelJumpsInEvenAfterScrolling() {
    var s = NotificationStore()
    s.post(note("c", level: .critical), now: 0)
    s.post(note("i"), now: 0)
    s.next(now: 1)  // the user looks at the info one
    s.post(note("w", level: .warning), now: 2)
    #expect(s.banner?.id == "w")
}

@Test func expiryAfterScrollingBringsUpTheHighest() {
    var s = NotificationStore()
    s.post(note("e", level: .error), now: 0)
    s.post(note("w", level: .warning), now: 0)
    s.post(note("i"), now: 0)
    s.previous(now: 1)  // wraps to i
    #expect(s.banner?.id == "i")
    s.tick(now: 7)
    #expect(s.banner?.id == "e")
}

@Test func queueListsTheWaitingInTheOrderNextBringsThem() {
    var s = NotificationStore()
    s.post(note("e", level: .error), now: 0)
    s.post(note("w", level: .warning), now: 0)
    s.post(note("i"), now: 0)
    #expect(s.queue.map(\.id) == ["w", "i"])
    s.next(now: 1)
    #expect(s.queue.map(\.id) == ["i", "e"])
}
