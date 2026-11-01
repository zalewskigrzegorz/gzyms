import Testing
@testable import GzymsCore

/// Feeds (time, pointer in the bar strip, ⌘ down) samples; returns at which times `yielded` flipped and the end state.
func yieldRun(_ samples: [(Double, Bool, Bool)]) -> (flips: [Double], yielded: Bool) {
    var y = MenuBarYield()
    let flips = samples.filter { y.update(now: $0.0, inStrip: $0.1, command: $0.2) }.map(\.0)
    return (flips, y.yielded)
}

@Test func commandHeldOnTheBarYieldsAfterHold() {
    let r = yieldRun([(0, true, true), (0.2, true, true), (0.3, true, true)])
    #expect(r.flips == [0.3])
    #expect(r.yielded)
}

@Test func releasingCommandEarlyCancels() {
    let r = yieldRun([(0, true, true), (0.2, true, false), (0.35, true, true)])
    #expect(r.flips == [])
}

@Test func commandOffTheBarDoesNothing() {
    #expect(yieldRun([(0, false, true), (1, false, true)]).flips == [])
}

@Test func comesBackAfterThePointerLeavesTheStrip() {
    // Moving between menus with ⌘ released keeps it yielded; 0.5 s off the strip brings it back.
    let r = yieldRun([(0, true, true), (0.3, true, true), (2, true, false), (3, false, false), (3.4, false, false), (3.5, false, false)])
    #expect(r.flips == [0.3, 3.5])
    #expect(!r.yielded)
}

@Test func briefExitDoesNotBringItBack() {
    let r = yieldRun([(0, true, true), (0.3, true, true), (1, false, false), (1.3, true, false), (1.9, false, false)])
    #expect(r.flips == [0.3])
    #expect(r.yielded)
}
