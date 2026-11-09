import Foundation
import Testing
@testable import GzymsCore

@Test func autoRestartNeedsTheSwitch() {
    let p = NCRestartPolicy()
    #expect(!p.mayAutoRestart(enabled: false, at: 1000))
    #expect(p.mayAutoRestart(enabled: true, at: 1000))
}

@Test func autoRestartWaitsForABannerAfterARestart() {
    var p = NCRestartPolicy()
    p.restarted(at: 1000)
    // Still hung after the restart: warn, never loop, however much time passes.
    #expect(!p.mayAutoRestart(enabled: true, at: 1000 + 3600))
    #expect(p.stillHung)
    p.bannerShown()
    #expect(!p.stillHung)
}

@Test func autoRestartAtMostOncePerTenMinutes() {
    var p = NCRestartPolicy()
    p.restarted(at: 1000)
    p.bannerShown()
    #expect(!p.mayAutoRestart(enabled: true, at: 1000 + 599))
    #expect(p.mayAutoRestart(enabled: true, at: 1000 + 600))
}

@Test func manualRestartCountsAndHoldsTheAutomatic() {
    var p = NCRestartPolicy()
    p.restarted(at: 5)
    p.restarted(at: 6)  // the button has no limit
    #expect(p.count == 2)
    #expect(p.last == 6)
    #expect(!p.mayAutoRestart(enabled: true, at: 10_000))
}

@Test func restartsTodayDropsEarlierDays() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
    let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14))!
    let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 0, minute: 5))!
    let lateYesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 55))!
    #expect(restartsToday([lateYesterday, morning, now], now: now, calendar: cal) == [morning, now])
    #expect(restartsToday([], now: now, calendar: cal).isEmpty)
}

@Test func focusIsOnWhenAnAssertionRecordExists() {
    let on = Data(#"{"data":[{"storeAssertionRecords":[{"x":1}],"storeInvalidationRecords":[]}]}"#.utf8)
    let off = Data(#"{"data":[{"storeAssertionRecords":[],"storeInvalidationRecords":[{"x":1}]}]}"#.utf8)
    #expect(focusIsOn(assertions: on))
    #expect(!focusIsOn(assertions: off))
    #expect(!focusIsOn(assertions: Data("nope".utf8)))
}
