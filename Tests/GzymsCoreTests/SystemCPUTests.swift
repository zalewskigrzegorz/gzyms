import Testing
@testable import GzymsCore

@Test func cpuPercentFromTickDeltas() {
    let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
    let b = CPUTicks(user: 130, system: 60, idle: 910, nice: 0)
    #expect(SystemCPU.percent(prev: a, now: b) == 40)
}

@Test func cpuPercentSurvivesCounterWrap() {
    // The kernel's tick counters are 32-bit and wrap after weeks of uptime.
    let a = CPUTicks(user: .max - 9, system: 0, idle: .max - 9, nice: 0)
    let b = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
    #expect(SystemCPU.percent(prev: a, now: b) == 50)
}

@Test func cpuPercentWithNoTicksIsZero() {
    let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
    #expect(SystemCPU.percent(prev: a, now: a) == 0)
}

@Test func cpuTicksFromThisMac() throws {
    let t = try #require(SystemCPU.ticks())
    #expect(t.idle > 0)
}
