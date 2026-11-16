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
    #expect(activeSource(.auto, hyprmac: true, omniwm: true, aerospace: true) == .omniwm)
    #expect(activeSource(.auto, hyprmac: true, omniwm: false, aerospace: true) == .hyprmac)
    #expect(activeSource(.auto, hyprmac: false, omniwm: false, aerospace: true) == .aerospace)
    #expect(activeSource(.auto, hyprmac: false, omniwm: false, aerospace: false) == .spaces)
    #expect(activeSource(.aerospace, hyprmac: true, omniwm: true, aerospace: false) == .aerospace)
}

@Test func onlyTilerLaunchesReResolveTheSource() {
    #expect(isWorkspaceTiler("bobko.aerospace") && isWorkspaceTiler("com.zachgray.HyprMac") && isWorkspaceTiler("com.zachgray.HyprMac.dev"))
    #expect(isWorkspaceTiler("com.barut.OmniWM"))
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
    #expect(loadConfig(toml: "[workspaces]\nsource = \"omniwm\"").config.workspaceSource == .omniwm)
    let bad = loadConfig(toml: "[workspaces]\nsource = \"yabai\"")
    #expect(bad.config.workspaceSource == .auto)
    #expect(bad.problems.contains { $0.contains("workspaces.source") })
}

// Shapes from `omniwmctl query workspaces --json` and `query windows --json`, OmniWM 0.8.0 (protocol 22). Titles left out.
private let omniWorkspaces = Data("""
{"id":"q1","kind":"query","ok":true,"status":"success","version":22,"result":{"kind":"workspaces","payload":{"workspaces":[
 {"counts":{"floating":0,"scratchpad":0,"tiled":1,"total":1},"display":{"id":"display:1","isMain":true,"name":"Built-in Retina Display"},"displayName":"chat","id":"A","isCurrent":false,"isFocused":false,"isVisible":false,"layout":"dwindle","number":1,"rawName":"1"},
 {"counts":{"floating":1,"scratchpad":0,"tiled":1,"total":2},"display":{"id":"display:1","isMain":true,"name":"Built-in Retina Display"},"displayName":"term","focusedWindowId":"ow_b","id":"B","isCurrent":true,"isFocused":true,"isVisible":true,"layout":"dwindle","number":2,"rawName":"2"},
 {"counts":{"floating":0,"scratchpad":0,"tiled":1,"total":1},"display":{"id":"display:2","isMain":false,"name":"DELL U3225QE"},"displayName":"web","id":"C","isCurrent":false,"isFocused":false,"isVisible":true,"layout":"niri","number":6,"rawName":"6"},
 {"counts":{"floating":0,"scratchpad":0,"tiled":0,"total":0},"display":{"id":"display:2","isMain":false,"name":"DELL U3225QE"},"displayName":"7","id":"D","isCurrent":false,"isFocused":false,"isVisible":false,"layout":"niri","number":7,"rawName":"7"},
 {"counts":{"floating":0,"scratchpad":0,"tiled":0,"total":0},"display":{"id":"display:2","isMain":false,"name":"DELL U3225QE"},"displayName":"extra","id":"E","isCurrent":false,"isFocused":false,"isVisible":false,"layout":"niri","number":11,"rawName":"11"},
 {"displayName":"broken","id":"F"}]}}}
""".utf8)
private let omniWindows = Data("""
{"id":"q2","kind":"query","ok":true,"status":"success","version":22,"result":{"kind":"windows","payload":{"windows":[
 {"app":{"bundleId":"com.mitchellh.ghostty","name":"Ghostty"},"display":{"id":"display:1","isMain":true,"name":"Built-in Retina Display"},"id":"ow_b","isFocused":true,"isScratchpad":false,"mode":"tiling","pid":1,"windowId":3843,"workspace":{"displayName":"term","id":"B","number":2,"rawName":"2"}},
 {"app":{"bundleId":"com.apple.calculator","name":"Calculator"},"id":"ow_c","isFocused":false,"isScratchpad":false,"mode":"floating","pid":2,"windowId":3850,"workspace":{"displayName":"term","id":"B","number":2,"rawName":"2"}},
 {"app":{"bundleId":"com.apple.Safari","name":"Safari"},"id":"ow_d","isFocused":false,"isScratchpad":false,"mode":"tiling","pid":3,"windowId":3927,"workspace":{"displayName":"web","id":"C","number":6,"rawName":"6"}},
 {"app":{"bundleId":"net.whatsapp.WhatsApp","name":"WhatsApp"},"id":"ow_e","isFocused":false,"isScratchpad":false,"mode":"tiling","pid":4,"windowId":4058,"workspace":{"displayName":"chat","id":"A","number":1,"rawName":"1"}},
 {"app":{"bundleId":"com.apple.Notes","name":"Notes"},"id":"ow_f","isFocused":false,"isScratchpad":true,"mode":"floating","pid":5,"windowId":4100,"workspace":{"displayName":"chat","id":"A","number":1,"rawName":"1"}},
 {"app":{"name":"java"},"id":"ow_g","isFocused":false,"isScratchpad":false,"mode":"tiling","pid":6,"windowId":4200,"workspace":{"displayName":"web","id":"C","number":6,"rawName":"6"}},
 {"id":"ow_h"}]}}}
""".utf8)

@Test func omniwmJSONBecomesTheBarState() throws {
    let s = try #require(omniwmState(workspaces: omniWorkspaces, windows: omniWindows))
    #expect(s.focusedWorkspace == 2)
    #expect(s.focusedMonitor == "Built-in Retina Display")
    #expect(s.monitors == [Monitor(name: "Built-in Retina Display", visibleWorkspace: 2, focused: true),
                           Monitor(name: "DELL U3225QE", visibleWorkspace: 6, focused: false)])
    #expect(s.workspaces.map(\.id) == [1, 2, 6, 7])  // 11 is past the bar, the broken entry is dropped
    #expect(s.workspaces.map(\.name) == ["chat", "term", "web", nil])  // a bare number is no name
    #expect(s.workspaces.map(\.visible) == [false, true, true, false])
    let term = try #require(s.workspaces.first { $0.id == 2 })
    #expect(term.windows == [Window(id: 3843, app: "Ghostty", bundleID: "com.mitchellh.ghostty", floating: false, focused: true),
                             Window(id: 3850, app: "Calculator", bundleID: "com.apple.calculator", floating: true, focused: false)])
    #expect(s.workspaces.first { $0.id == 1 }?.windows.map(\.bundleID) == ["net.whatsapp.WhatsApp"])  // scratchpad left out
    #expect(s.workspaces.first { $0.id == 6 }?.windows.map(\.bundleID) == ["com.apple.Safari", ""])
    let bar = barWorkspaces(state: s, styles: WorkspaceStyle.gregDefaults, showEmpty: false)
    #expect(bar.map(\.label) == ["1", "2", "6"])
    #expect(bar.first { $0.isActive }?.number == 2)
}

@Test func unreadableOmniwmListIsNil() {
    let refused = Data(#"{"ok":false,"status":"error","code":"transport_failure"}"#.utf8)
    #expect(omniwmState(workspaces: refused, windows: Data()) == nil)
    // Workspaces without the window list still draw, with no apps.
    #expect(omniwmState(workspaces: omniWorkspaces, windows: Data())?.workspaces.allSatisfy { $0.windows.isEmpty } == true)
}

@Test func omniwmEmptyCurrentWorkspaceIsTheActiveOne() throws {
    // Read live on workspace 5 with no windows: OmniWM says isCurrent, not isFocused.
    let ws = Data(#"{"result":{"kind":"workspaces","payload":{"workspaces":[{"display":{"name":"M"},"displayName":"term","isCurrent":false,"isFocused":false,"isVisible":false,"number":2},{"display":{"name":"M"},"displayName":"notes","isCurrent":true,"isFocused":false,"isVisible":true,"number":5}]}}}"#.utf8)
    let s = try #require(omniwmState(workspaces: ws, windows: Data()))
    #expect(s.focusedWorkspace == 5 && s.monitors == [Monitor(name: "M", visibleWorkspace: 5, focused: true)])
    #expect(barWorkspaces(state: s, styles: WorkspaceStyle.gregDefaults, showEmpty: false).map(\.isActive) == [true])
}
