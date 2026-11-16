import Foundation

/// `[workspaces] source`: where the bar's workspaces come from. Every source produces a `HyprMacState`, so the bar does not care.
public enum WorkspaceSource: String, CaseIterable, Sendable {
    case auto, hyprmac, omniwm, aerospace, spaces

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .hyprmac: "HyprMac"
        case .omniwm: "OmniWM"
        case .aerospace: "AeroSpace"
        case .spaces: "macOS Spaces"
        }
    }

    /// Where to get the tiler. nil = nothing to install.
    public var homepage: String? {
        switch self {
        case .hyprmac: "https://hyprmac.app"
        case .omniwm: "https://github.com/OmniNull/OmniWM"
        case .aerospace: "https://nikitabobko.github.io/AeroSpace/guide"
        case .auto, .spaces: nil
        }
    }
}

public let omniwmBundleID = "com.barut.OmniWM"

/// Auto takes the tiler that runs, OmniWM first: it is seen by its process alone, while HyprMac also counts through
/// its state file and a 10 s grace, so a move from HyprMac to OmniWM would otherwise keep HyprMac's old state.
/// Without a tiler, macOS Spaces: they are always there.
public func activeSource(_ setting: WorkspaceSource, hyprmac: Bool, omniwm: Bool, aerospace: Bool) -> WorkspaceSource {
    guard setting == .auto else { return setting }
    return omniwm ? .omniwm : hyprmac ? .hyprmac : aerospace ? .aerospace : .spaces
}

/// The apps whose launch or quit can change what auto resolves to.
public func isWorkspaceTiler(_ bundleID: String) -> Bool {
    bundleID == "bobko.aerospace" || bundleID == omniwmBundleID || bundleID.hasPrefix("com.zachgray.HyprMac")
}

// MARK: - OmniWM

/// `omniwmctl query workspaces --json` and `query windows --json`. Workspaces keep OmniWM's number (1…10 on the bar),
/// the display name ("web") becomes the name. Scratchpad windows are left out: they belong to no workspace on screen.
/// nil = the workspace list is unreadable.
public func omniwmState(workspaces: Data, windows: Data) -> HyprMacState? {
    guard let list = try? JSONDecoder().decode(OmniReply<OmniWorkspaces>.self, from: workspaces) else { return nil }
    let all = list.result.payload.workspaces.compactMap(\.value).filter { (1...10).contains($0.number) }
    let wins = ((try? JSONDecoder().decode(OmniReply<OmniWindows>.self, from: windows))?.result.payload.windows ?? [])
        .compactMap(\.value).filter { $0.isScratchpad != true }
    let spaces = all.map { o in
        let w = wins.filter { $0.workspace?.number == o.number }.map {
            Window(id: $0.windowId, app: $0.app?.name ?? "", bundleID: $0.app?.bundleId ?? "", floating: $0.mode == "floating", focused: $0.isFocused == true)
        }
        return Workspace(id: o.number, name: o.displayName == String(o.number) ? nil : o.displayName, monitor: o.display?.name ?? "", visible: o.isVisible == true, windows: w)
    }
    // `isCurrent`, not `isFocused`: OmniWM marks focused only the workspace holding the focused window, so an empty one never is.
    let focused = all.first { $0.isCurrent == true }
    let monitors = all.filter { $0.isVisible == true }.map { Monitor(name: $0.display?.name ?? "", visibleWorkspace: $0.number, focused: $0.isCurrent == true) }
    return HyprMacState(focusedWorkspace: focused?.number, focusedMonitor: focused?.display?.name, monitors: monitors, workspaces: spaces)
}

private struct OmniReply<P: Decodable>: Decodable {
    struct Result: Decodable { let payload: P }
    let result: Result
}

private struct OmniName: Decodable { let name: String? }

private struct OmniWorkspaces: Decodable {
    struct Item: Decodable {
        let number: Int
        let displayName: String?
        let isCurrent: Bool?
        let isVisible: Bool?
        let display: OmniName?
    }
    let workspaces: [Lenient<Item>]
}

private struct OmniWindows: Decodable {
    struct Item: Decodable {
        struct App: Decodable { let bundleId: String?; let name: String? }
        struct Space: Decodable { let number: Int? }
        let windowId: Int
        let app: App?
        let workspace: Space?
        let mode: String?
        let isFocused: Bool?
        let isScratchpad: Bool?
    }
    let windows: [Lenient<Item>]
}

// MARK: - AeroSpace

/// The `--format` Gzyms passes with `--json`. AeroSpace names each JSON key after its format variable.
public let aerospaceWorkspaceFormat = "%{workspace} %{workspace-is-focused} %{workspace-is-visible} %{monitor-name}"
public let aerospaceWindowFormat = "%{window-id} %{app-bundle-id} %{workspace}"

/// The bar numbers workspaces 1…10. Names "1"…"10" keep their number, other names take the free ones in AeroSpace's order.
/// shortcut: a lettered workspace's number shifts when a numbered one appears or goes; fine while the set stays put.
public func aerospaceIDs(_ names: [String]) -> [String: Int] {
    var out: [String: Int] = [:]
    for n in names { if let i = Int(n), String(i) == n, (1...10).contains(i) { out[n] = i } }
    var free = (1...10).filter { !out.values.contains($0) }.makeIterator()
    for n in names where out[n] == nil {
        guard let i = free.next() else { break }
        out[n] = i
    }
    return out
}

/// `list-workspaces --all --json` and `list-windows --all --json` with the formats above. nil = the workspace list is unreadable.
public func aerospaceState(workspaces: Data, windows: Data) -> HyprMacState? {
    guard let list = try? JSONDecoder().decode([Lenient<AeroWorkspace>].self, from: workspaces) else { return nil }
    let all = list.compactMap(\.value)
    let wins = ((try? JSONDecoder().decode([Lenient<AeroWindow>].self, from: windows)) ?? []).compactMap(\.value)
    let ids = aerospaceIDs(all.map(\.workspace))
    let spaces = all.compactMap { a -> Workspace? in
        guard let id = ids[a.workspace] else { return nil }
        let w = wins.filter { $0.workspace == a.workspace }.map { Window(id: $0.id, app: $0.bundle, bundleID: $0.bundle, floating: false, focused: false) }
        var ws = Workspace(id: id, name: a.workspace == String(id) ? nil : a.workspace, monitor: a.monitor ?? "", visible: a.visible == true, windows: w)
        ws.label = a.workspace
        return ws
    }
    let focused = all.first { $0.focused == true }
    let monitors = all.filter { $0.visible == true }.compactMap { a in
        ids[a.workspace].map { Monitor(name: a.monitor ?? "", visibleWorkspace: $0, focused: a.focused == true) }
    }
    return HyprMacState(focusedWorkspace: focused.flatMap { ids[$0.workspace] }, focusedMonitor: focused?.monitor, monitors: monitors, workspaces: spaces)
}

private struct AeroWorkspace: Decodable {
    let workspace: String
    let focused: Bool?
    let visible: Bool?
    let monitor: String?
    enum CodingKeys: String, CodingKey {
        case workspace, focused = "workspace-is-focused", visible = "workspace-is-visible", monitor = "monitor-name"
    }
}

private struct AeroWindow: Decodable {
    let id: Int
    let bundle: String
    let workspace: String
    enum CodingKeys: String, CodingKey { case id = "window-id", bundle = "app-bundle-id", workspace }
}

// MARK: - macOS Spaces

/// One display's Mission Control spaces, from `CGSCopyManagedDisplaySpaces`. Desktops only: full-screen apps are left out,
/// the "Switch to Desktop N" shortcuts do not count them either.
public struct SpaceDisplay: Equatable, Sendable {
    /// "Main" while "Displays have separate Spaces" is off, else the display's UUID.
    public var id: String
    public var current: UInt64
    public var desktops: [UInt64]

    public init(id: String, current: UInt64, desktops: [UInt64]) {
        self.id = id; self.current = current; self.desktops = desktops
    }
}

public func spaceDisplays(_ raw: [[String: Any]]) -> [SpaceDisplay] {
    func spaceID(_ d: [String: Any]?) -> UInt64? { (d?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? (d?["id64"] as? NSNumber)?.uint64Value }
    return raw.compactMap { d in
        guard let id = d["Display Identifier"] as? String else { return nil }
        let desktops = ((d["Spaces"] as? [[String: Any]]) ?? []).filter { ($0["type"] as? NSNumber)?.intValue == 0 }.compactMap(spaceID)
        return SpaceDisplay(id: id, current: spaceID(d["Current Space"] as? [String: Any]) ?? 0, desktops: desktops)
    }
}

/// Desktops numbered 1…10 across displays, in Mission Control's order. `screenNames` maps a display id to its screen's name.
public func spacesState(displays: [SpaceDisplay], screenNames: [String: String], active: UInt64, windows: [(bundleID: String, spaces: [UInt64])]) -> HyprMacState {
    var workspaces: [Workspace] = []
    var monitors: [Monitor] = []
    var number: [UInt64: Int] = [:]
    for d in displays {
        let name = screenNames[d.id] ?? d.id
        for space in d.desktops where workspaces.count < 10 {
            let id = workspaces.count + 1
            number[space] = id
            let apps = windows.filter { $0.spaces.contains(space) }.map(\.bundleID)
            workspaces.append(Workspace(id: id, name: nil, monitor: name, visible: space == d.current,
                                        windows: apps.enumerated().map { Window(id: $0.offset, app: $0.element, bundleID: $0.element, floating: false, focused: false) }))
        }
        if let n = number[d.current] { monitors.append(Monitor(name: name, visibleWorkspace: n, focused: d.desktops.contains(active))) }
    }
    return HyprMacState(focusedWorkspace: number[active], focusedMonitor: monitors.first(where: \.focused)?.name, monitors: monitors, workspaces: workspaces)
}

public struct KeyCombo: Equatable, Sendable {
    public var keyCode: UInt16
    /// The same bits as `CGEventFlags` (control = 0x40000).
    public var flags: UInt64
}

/// The "Switch to Desktop N" shortcut from `com.apple.symbolichotkeys`, keys 118… for desktops 1…. nil = off or never set.
public func desktopShortcut(_ hotkeys: [String: Any], desktop: Int) -> KeyCombo? {
    guard (1...10).contains(desktop), let entry = hotkeys[String(117 + desktop)] as? [String: Any],
          (entry["enabled"] as? NSNumber)?.boolValue == true,
          let p = ((entry["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue), p.count == 3,
          let key = UInt16(exactly: p[1]), let flags = UInt64(exactly: p[2])
    else { return nil }
    return KeyCombo(keyCode: key, flags: flags)
}
