import Foundation
import Testing
@testable import GzymsCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func decoded(_ name: String) throws -> HyprMacState {
    guard case let .fresh(s) = readState(try fixture(name), previous: nil) else {
        Issue.record("\(name) did not decode"); throw CancellationError()
    }
    return s
}

@Test func decodesTwoMonitors() throws {
    let s = try decoded("state-two-monitors.json")
    #expect(s.monitors.count == 2)
    #expect(s.focusedWorkspace == 4)
    let ws4 = try #require(s.workspaces.first { $0.id == 4 })
    #expect(ws4.windows.count == 1)
    #expect(ws4.windows[0].bundleID == "com.mitchellh.ghostty")
}

@Test func ignoresUnknownKeys() throws {
    #expect(try decoded("state-unknown-keys.json") == decoded("state-two-monitors.json"))
}

@Test func truncatedFileKeepsPreviousAsStale() throws {
    let s = try decoded("state-two-monitors.json")
    #expect(readState(try fixture("state-truncated.json"), previous: s) == .stale(s, reason: "decode"))
}

@Test func missingFileWithPreviousIsStale() throws {
    let s = try decoded("state-two-monitors.json")
    #expect(readState(nil, previous: s) == .stale(s, reason: "missing"))
    #expect(readState(nil, previous: nil) == .none)
}

@Test func dropsWorkspaceIdsOutsideOneToTen() throws {
    let s = try decoded("state-bad-ids.json")
    #expect(s.workspaces.map(\.id) == [1, 2, 4])
}
