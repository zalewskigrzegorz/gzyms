import Foundation
import Testing
@testable import GzymsCore

@Test func heldDropsOlderThanWindow() {
    var h = HeldSeries(window: 60)
    h.add(5, at: 0)
    h.add(7, at: 30)
    h.add(1, at: 61)
    #expect(h.values == [7, 1])
}

@Test func heldMaxOverWindow() {
    var h = HeldSeries(window: 60)
    for (i, v) in [3.0, 9, 2].enumerated() { h.add(v, at: Double(i)) }
    #expect(h.max == 9)
    #expect(HeldSeries(window: 60).max == 0)
}

@Test func cpuPercentFromDeltas() {
    #expect(ProcessUsage.cpuPercent(prev: 10, now: 11.5, wall: 2) == 75)
    #expect(ProcessUsage.cpuPercent(prev: 10, now: 11, wall: 0) == 0)
}

@Test func sampleOwnProcess() throws {
    let pid = ProcessInfo.processInfo.processIdentifier
    let a = try #require(ProcessUsage.sample(pid: pid))
    var x = 0.0
    for i in 0..<5_000_000 { x += sqrt(Double(i)) }
    #expect(x > 0)
    let b = try #require(ProcessUsage.sample(pid: pid))
    #expect(a.residentMB > 0)
    #expect(b.cpuSeconds > a.cpuSeconds)
}

@Test func sampleDeadPidIsNil() {
    #expect(ProcessUsage.sample(pid: 999_999) == nil)
}
