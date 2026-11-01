import Testing
@testable import GzymsCore

func win(_ id: Int, _ bundle: String) -> Window {
    Window(id: id, app: bundle, bundleID: bundle, floating: false, focused: false)
}

func ws(_ id: Int, _ windows: [Window] = [], monitor: String = "M", visible: Bool = false) -> Workspace {
    Workspace(id: id, name: nil, monitor: monitor, visible: visible, windows: windows)
}

let sample = HyprMacState(
    focusedWorkspace: 4, focusedMonitor: "M",
    monitors: [Monitor(name: "M", visibleWorkspace: 4, focused: true)],
    workspaces: [ws(1, [win(1, "com.mitchellh.ghostty")]), ws(2), ws(4, visible: true)])

@Test func hidesEmptyWorkspacesByDefault() {
    let bar = barWorkspaces(state: sample, styles: WorkspaceStyle.gregDefaults, showEmpty: false)
    #expect(bar.map(\.number) == [1, 4])
    #expect(bar.map(\.isActive) == [false, true])
}

@Test func showEmptyShowsAllTen() {
    #expect(barWorkspaces(state: sample, styles: WorkspaceStyle.gregDefaults, showEmpty: true).count == 10)
}

@Test func usesGregColours() {
    let bar = barWorkspaces(state: sample, styles: WorkspaceStyle.gregDefaults, showEmpty: true)
    #expect(bar[1].color == "peach")
    #expect(bar[5].color == "sky")
}

@Test func appBundleIDsInWindowOrderWithoutDuplicates() {
    var s = sample
    s.workspaces[0].windows = [win(1, "com.mitchellh.ghostty"), win(2, "com.tinyspeck.slackmacgap"), win(3, "com.mitchellh.ghostty")]
    let bar = barWorkspaces(state: s, styles: WorkspaceStyle.gregDefaults, showEmpty: false)
    #expect(bar[0].appBundleIDs == ["com.mitchellh.ghostty", "com.tinyspeck.slackmacgap"])
}

@Test func sameNameMonitorsMapByPosition() {
    let left = ScreenSlot(displayID: 7, localizedName: "DELL U3225QE", originX: -2560)
    let right = ScreenSlot(displayID: 3, localizedName: "DELL U3225QE", originX: 1512)
    let laptop = ScreenSlot(displayID: 1, localizedName: "Built-in Retina Display", originX: 0)
    let state = [Monitor(name: "DELL U3225QE", visibleWorkspace: 6, focused: false),
                 Monitor(name: "Built-in Retina Display", visibleWorkspace: 2, focused: true),
                 Monitor(name: "DELL U3225QE", visibleWorkspace: 3, focused: false)]
    let all = [right, laptop, left]
    #expect(monitorIndex(for: left, all: all, stateMonitors: state) == 0)
    #expect(monitorIndex(for: right, all: all, stateMonitors: state) == 2)
    #expect(monitorIndex(for: laptop, all: all, stateMonitors: state) == 1)
    #expect(monitorIndex(for: ScreenSlot(displayID: 9, localizedName: "LG", originX: 0), all: all, stateMonitors: state) == nil)
}

@Test func ignoresUnknownBundleIDsGracefully() {
    var s = sample
    s.workspaces[0].windows = [win(1, "")]
    #expect(barWorkspaces(state: s, styles: WorkspaceStyle.gregDefaults, showEmpty: false)[0].appBundleIDs == [])
}

@Test func withoutATilerTheBarIsOneDesktop() {
    let ws = singleDesktop(styles: WorkspaceStyle.gregDefaults, apps: ["com.a", "com.b"])
    #expect(ws == [BarWorkspace(number: 1, color: WorkspaceStyle.gregDefaults[0].color, isActive: true, appBundleIDs: ["com.a", "com.b"])])
}
