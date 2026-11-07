import Foundation

/// `[workspaces] source`: where the bar's workspaces come from. Every source produces a `HyprMacState`, so the bar does not care.
public enum WorkspaceSource: String, CaseIterable, Sendable {
    case auto, hyprmac, aerospace, spaces

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .hyprmac: "HyprMac"
        case .aerospace: "AeroSpace"
        case .spaces: "macOS Spaces"
        }
    }

    /// Where to get the tiler. nil = nothing to install.
    public var homepage: String? {
        switch self {
        case .hyprmac: "https://github.com/zacharytgray/HyprMac"
        case .aerospace: "https://github.com/nikitabobko/AeroSpace"
        case .auto, .spaces: nil
        }
    }
}

/// Auto takes the tiler that runs, HyprMac first. Without one, macOS Spaces: they are always there.
public func activeSource(_ setting: WorkspaceSource, hyprmac: Bool, aerospace: Bool) -> WorkspaceSource {
    guard setting == .auto else { return setting }
    return hyprmac ? .hyprmac : aerospace ? .aerospace : .spaces
}

/// The apps whose launch or quit can change what auto resolves to.
public func isWorkspaceTiler(_ bundleID: String) -> Bool {
    bundleID == "bobko.aerospace" || bundleID.hasPrefix("com.zachgray.HyprMac")
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
