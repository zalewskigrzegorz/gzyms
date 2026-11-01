import Foundation
import Testing
@testable import GzymsCore

let t0 = Date(timeIntervalSince1970: 1_793_400_000)
let sampleVitals = Vitals(pid: 42, at: t0, lagMs: 3.5, panels: 2, rebuilds: 1, eventsPerSec: 0.5)

@Test func vitalsRoundTripJSON() throws {
    let data = try JSONEncoder().encode(sampleVitals)
    #expect(try JSONDecoder().decode(Vitals.self, from: data) == sampleVitals)
}

@Test func freshWithinTwoSeconds() {
    #expect(vitalsFreshness(sampleVitals, now: t0.addingTimeInterval(1.9)) == .fresh(sampleVitals))
}

@Test func notAnsweringAfterTwoSeconds() {
    #expect(vitalsFreshness(sampleVitals, now: t0.addingTimeInterval(2.1)) == .notAnswering(since: t0))
}

@Test func missingWhenNil() {
    #expect(vitalsFreshness(nil, now: t0) == .missing)
}

@Test func pongReturnsLatency() {
    var t = StallTracker(threshold: 0.25)
    _ = t.tick(at: 0)
    #expect(t.pong(at: 0.04) == 0.04)
    #expect(t.pong(at: 0.05) == nil)  // no ping out
}

@Test func rateCounterCountsLastSecond() {
    var r = RateCounter(window: 1)
    for at in [0.1, 0.5, 0.9, 1.5] { r.hit(at: at) }
    #expect(r.perSecond(at: 1.6) == 2)
}
