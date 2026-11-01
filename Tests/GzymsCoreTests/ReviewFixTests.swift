import Foundation
import Testing
@testable import GzymsCore

// Fixes from the M1 final review. Each test failed before its fix.

@Test func windowWithoutBundleIDAndBrokenEntryDoNotBreakDecoding() throws {
    let s = try decoded("state-messy-entries.json")
    #expect(s.workspaces.map(\.id) == [1, 2, 4])
    let ws2 = try #require(s.workspaces.first { $0.id == 2 })
    #expect(ws2.windows.count == 2)
    #expect(ws2.windows[1].bundleID == "")
}

@Test func wrongTypeKeepsTheOtherKeys() {
    let load = loadConfig(toml: """
    [workspaces]
    show_empty = "yes"

    [[workspaces.style]]
    number = 2
    color = "#FF0000"
    """)
    #expect(load.config.workspaces[1].color == "#FF0000")
    #expect(load.config.showEmpty == false)
    #expect(load.problems.contains { $0.contains("workspaces.show_empty") })
}

@Test func unknownKeyInsideStyleIsReported() {
    let load = loadConfig(toml: """
    [[workspaces.style]]
    number = 2
    colour = "#FF0000"
    """)
    #expect(load.problems.contains { $0.contains("workspaces.style[2].colour") })
}

@Test func unplugHidesThenDestroysAfterGrace() {
    var life = PanelLifecycle(grace: 10)
    let a = life.apply(planDisplays(current: [1, 2], next: [1]), at: 0)
    #expect(a == PanelActions(create: [], reshow: [], hide: [2]))
    #expect(life.expire(at: 5) == [])
    #expect(life.expire(at: 10) == [2])
}

@Test func replugWithinGraceReshowsSamePanel() {
    var life = PanelLifecycle(grace: 10)
    _ = life.apply(planDisplays(current: [1, 2], next: [1]), at: 0)
    let a = life.apply(planDisplays(current: [1], next: [1, 2]), at: 3)
    #expect(a == PanelActions(create: [], reshow: [2], hide: []))
    #expect(life.expire(at: 20) == [])
}

@Test func hyprMacExitMarksStateStale() {
    let s = HyprMacState(focusedWorkspace: 1, focusedMonitor: nil, monitors: [], workspaces: [])
    #expect(stateAfterAppExit(bundleID: "com.zachgray.HyprMac", current: .fresh(s)) == .stale(s, reason: "hyprmac quit"))
    #expect(stateAfterAppExit(bundleID: "com.tinyspeck.slackmacgap", current: .fresh(s)) == nil)
}
