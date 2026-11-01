import Testing
@testable import GzymsCore

@Test func sameDisplaysKeepEverything() {
    #expect(planDisplays(current: [1, 2], next: [1, 2]) == DisplayPlan(keep: [1, 2], create: [], destroy: []))
}

@Test func unplugMonitorDestroysOnlyIt() {
    #expect(planDisplays(current: [1, 2], next: [1]) == DisplayPlan(keep: [1], create: [], destroy: [2]))
}

@Test func plugMonitorCreatesOnlyIt() {
    #expect(planDisplays(current: [1], next: [1, 3]) == DisplayPlan(keep: [1], create: [3], destroy: []))
}

@Test func emptyNextDuringSleepKeepsCurrent() {
    // During wake the screen list is empty for a moment; tearing everything down here is the SketchyBar bug.
    #expect(planDisplays(current: [1, 2], next: []) == DisplayPlan(keep: [1, 2], create: [], destroy: []))
}

@Test func planIsEmptyOnlyWhenNothingChanges() {
    #expect(planDisplays(current: [1], next: [1]).changesNothing)
    #expect(!planDisplays(current: [1], next: [2]).changesNothing)
}
