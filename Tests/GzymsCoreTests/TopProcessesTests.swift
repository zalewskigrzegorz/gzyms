import Foundation
import Testing
@testable import GzymsCore

@Test func topProcessesInPercentOfOneCore() {
    // Like Activity Monitor: 2 CPU seconds in 2 s is one full core = 100%; 3 cores' worth = 300%.
    let prev: [Int32: Double] = [1: 10, 2: 5, 3: 1, 5: 0]
    let now: [Int32: Double] = [1: 12, 2: 5.4, 3: 1, 4: 0.2, 5: 6]
    let top = TopProcesses.top(prev: prev, now: now, wall: 2, count: 3)
    #expect(top.map(\.pid) == [5, 1, 2])
    #expect(top[0].percent == 300)
    #expect(top[1].percent == 100)
    #expect(abs(top[2].percent - 20) < 0.0001)
}

@Test func topProcessesSkipsNewAndIdle() {
    // pid 4 has no previous sample (its whole lifetime would count as now); idle ones are noise.
    let top = TopProcesses.top(prev: [1: 3], now: [1: 3, 4: 50], wall: 2, count: 5)
    #expect(top.isEmpty)
}

@Test func psOutputParses() {
    let out = """
      421 428:17.48 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
    44099   0:03.10 /Users/alex/.local/bin/claude
      777   1:02:03.50 /usr/libexec/long running thing
    garbage line
    """
    let p = TopProcesses.parse(ps: out)
    #expect(p[421]?.cpu == 428 * 60 + 17.48)
    #expect(p[421]?.name == "WindowServer")
    #expect(p[44099]?.cpu == 3.1)
    #expect(p[777]?.cpu == 3723.5)
    #expect(p[777]?.name == "long running thing")
    #expect(p.count == 3)
}

@Test func psSeesSystemProcesses() {
    // launchd (pid 1) runs as root: the reason for going through ps.
    #expect(TopProcesses.snapshot()[1] != nil)
}
