import Foundation
import Testing
@testable import GzymsCore

@Test func caffeineLabelCountsDownRoundedUp() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(CaffeineState(until: now.addingTimeInterval(105 * 60)).label(now: now) == "1h45")
    #expect(CaffeineState(until: now.addingTimeInterval(120 * 60)).label(now: now) == "2h")
    #expect(CaffeineState(until: now.addingTimeInterval(24 * 60 + 10)).label(now: now) == "25m")
    #expect(CaffeineState(until: now.addingTimeInterval(5)).label(now: now) == "1m")  // never 0 while on
    #expect(CaffeineState(until: .distantFuture).label(now: now) == "∞")
    #expect(CaffeineState.steps.first == 15 && CaffeineState.steps.last == 480 && CaffeineState.steps.count == 32)
}

@Test func caffeineSurvivesARestartOnlyWhileItsProcessLives() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let timed = CaffeineState.Record(pid: 42, until: 1600, display: false)
    #expect(timed.live(now: now, alive: true))
    #expect(!timed.live(now: now, alive: false))                                  // caffeinate is gone
    #expect(!timed.live(now: Date(timeIntervalSince1970: 1700), alive: true))     // its time ran out (pid reused?)
    #expect(CaffeineState.Record(pid: 42, until: nil, display: true).live(now: now, alive: true))
    #expect(timed.state.label(now: now) == "10m")
    let back = try JSONDecoder().decode(CaffeineState.Record.self, from: JSONEncoder().encode(timed))
    #expect(back == timed)
    #expect(CaffeineState.command(seconds: 600, display: true) == ["/usr/bin/caffeinate", "-i", "-d", "-t", "600"])
    #expect(CaffeineState.command(seconds: nil, display: false) == ["/usr/bin/caffeinate", "-i"])
}

@Test func caffeineStopsOnALowBatteryOnlyWhenAsked() {
    #expect(CaffeineState.batteryTooLow(percent: 19, charging: false, threshold: 20))
    #expect(!CaffeineState.batteryTooLow(percent: 19, charging: true, threshold: 20))
    #expect(!CaffeineState.batteryTooLow(percent: 19, charging: false, threshold: 0))
    #expect(!CaffeineState.batteryTooLow(percent: nil, charging: false, threshold: 20))  // a desktop Mac
}
