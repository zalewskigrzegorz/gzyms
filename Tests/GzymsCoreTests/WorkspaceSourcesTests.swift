import Foundation
import Testing
@testable import GzymsCore

// Shapes from AeroSpace's formatToJson (keys = format variable names, typed values), v0.21.3.
private let aeroWorkspaces = Data("""
[{"workspace":"1","workspace-is-focused":false,"workspace-is-visible":false,"monitor-name":"Built-in Retina Display"},
 {"workspace":"2","workspace-is-focused":true,"workspace-is-visible":true,"monitor-name":"Built-in Retina Display"},
 {"workspace":"B","workspace-is-focused":false,"workspace-is-visible":true,"monitor-name":"DELL U3225QE"},
 {"workspace":"web","workspace-is-focused":false,"workspace-is-visible":false,"monitor-name":"DELL U3225QE"}]
""".utf8)
private let aeroWindows = Data("""
[{"window-id":11,"app-bundle-id":"com.mitchellh.ghostty","workspace":"2"},
 {"window-id":12,"app-bundle-id":"com.apple.Safari","workspace":"web"},
 {"window-id":"broken","workspace":"1"}]
""".utf8)

@Test func aerospaceNamesKeepTheirNumberOrTakeAFreeOne() {
    #expect(aerospaceIDs(["1", "2", "B", "web", "01"]) == ["1": 1, "2": 2, "B": 3, "web": 4, "01": 5])
    #expect(aerospaceIDs((1...12).map { "w\($0)" }).count == 10)
}

@Test func aerospaceJSONBecomesTheBarState() throws {
    let s = try #require(aerospaceState(workspaces: aeroWorkspaces, windows: aeroWindows))
    #expect(s.focusedWorkspace == 2)
    #expect(s.focusedMonitor == "Built-in Retina Display")
    #expect(s.monitors == [Monitor(name: "Built-in Retina Display", visibleWorkspace: 2, focused: true),
                           Monitor(name: "DELL U3225QE", visibleWorkspace: 3, focused: false)])
    let web = try #require(s.workspaces.first { $0.label == "web" })
    #expect(web.id == 4 && web.name == "web" && web.windows.map(\.bundleID) == ["com.apple.Safari"])
    #expect(s.workspaces.first { $0.id == 2 }?.name == nil)  // "2" is its own number, no extra name
    let bar = barWorkspaces(state: s, styles: WorkspaceStyle.gregDefaults, showEmpty: false)
    #expect(bar.map(\.label) == ["2", "B", "web"])
}

@Test func unreadableAerospaceListIsNil() {
    #expect(aerospaceState(workspaces: Data("aerospace: not running".utf8), windows: Data()) == nil)
}

@Test func spacesNumberDesktopsAcrossDisplaysAndSkipFullScreen() {
    let raw: [[String: Any]] = [
        ["Display Identifier": "UUID-A", "Current Space": ["ManagedSpaceID": 5], "Spaces": [
            ["ManagedSpaceID": 1, "type": 0], ["ManagedSpaceID": 9, "type": 4], ["ManagedSpaceID": 5, "type": 0]]],
        ["Display Identifier": "UUID-B", "Current Space": ["id64": 7], "Spaces": [["id64": 7, "type": 0]]],
    ]
    let displays = spaceDisplays(raw)
    #expect(displays == [SpaceDisplay(id: "UUID-A", current: 5, desktops: [1, 5]), SpaceDisplay(id: "UUID-B", current: 7, desktops: [7])])
    let s = spacesState(displays: displays, screenNames: ["UUID-A": "Built-in Retina Display"], active: 7,
                        windows: [("com.apple.Safari", [1]), ("com.mitchellh.ghostty", [5, 7])])
    #expect(s.focusedWorkspace == 3)
    #expect(s.workspaces.map(\.monitor) == ["Built-in Retina Display", "Built-in Retina Display", "UUID-B"])
    #expect(s.workspaces.map(\.visible) == [false, true, true])
    #expect(s.workspaces.map { $0.windows.map(\.bundleID) } == [["com.apple.Safari"], ["com.mitchellh.ghostty"], ["com.mitchellh.ghostty"]])
    #expect(s.monitors.map(\.focused) == [false, true])
}

@Test func desktopShortcutReadsOnlyEnabledEntries() {
    let hotkeys: [String: Any] = [
        "118": ["enabled": true, "value": ["parameters": [65535, 18, 262144], "type": "standard"]],
        "119": ["enabled": false, "value": ["parameters": [65535, 19, 262144], "type": "standard"]],
    ]
    #expect(desktopShortcut(hotkeys, desktop: 1) == KeyCombo(keyCode: 18, flags: 0x40000))
    #expect(desktopShortcut(hotkeys, desktop: 2) == nil)
    #expect(desktopShortcut(hotkeys, desktop: 3) == nil)
}

@Test func autoTakesTheTilerThatRuns() {
    #expect(activeSource(.auto, hyprmac: true, aerospace: true) == .hyprmac)
    #expect(activeSource(.auto, hyprmac: false, aerospace: true) == .aerospace)
    #expect(activeSource(.auto, hyprmac: false, aerospace: false) == .spaces)
    #expect(activeSource(.aerospace, hyprmac: true, aerospace: false) == .aerospace)
}

@Test func onlyTilerLaunchesReResolveTheSource() {
    #expect(isWorkspaceTiler("bobko.aerospace") && isWorkspaceTiler("com.zachgray.HyprMac") && isWorkspaceTiler("com.zachgray.HyprMac.dev"))
    #expect(!isWorkspaceTiler("com.apple.Safari"))
}

@Test func aerospaceWithOnlyLetterNames() throws {
    let ws = Data(#"[{"workspace":"B","workspace-is-focused":true,"workspace-is-visible":true,"monitor-name":"M"},{"workspace":"web","workspace-is-focused":false,"workspace-is-visible":false,"monitor-name":"M"}]"#.utf8)
    let win = Data(#"[{"window-id":1,"app-bundle-id":"com.apple.Safari","workspace":"web"}]"#.utf8)
    let s = try #require(aerospaceState(workspaces: ws, windows: win))
    #expect(s.focusedWorkspace == 1 && s.workspaces.map(\.label) == ["B", "web"])
    #expect(barWorkspaces(state: s, styles: WorkspaceStyle.gregDefaults, showEmpty: false).map(\.label) == ["B", "web"])
}

@Test func workspaceSourceFromConfig() {
    #expect(loadConfig(toml: "[workspaces]\nsource = \"aerospace\"").config.workspaceSource == .aerospace)
    let bad = loadConfig(toml: "[workspaces]\nsource = \"yabai\"")
    #expect(bad.config.workspaceSource == .auto)
    #expect(bad.problems.contains { $0.contains("workspaces.source") })
}
