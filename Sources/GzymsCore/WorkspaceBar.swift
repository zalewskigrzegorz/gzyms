/// Name and colour of one workspace, set by the user (e.g. to match a keyboard backlight).
public struct WorkspaceStyle: Equatable, Sendable {
    public var number: Int
    public var name: String
    public var color: String

    public init(number: Int, name: String, color: String) {
        self.number = number
        self.name = name
        self.color = color
    }

    /// Greg's map, carried over from his SketchyBar `spaces.lua`.
    public static let gregDefaults: [WorkspaceStyle] = [
        .init(number: 1, name: "chat", color: "green"), .init(number: 2, name: "term", color: "peach"),
        .init(number: 3, name: "code", color: "pink"), .init(number: 4, name: "misc", color: "overlay"),
        .init(number: 5, name: "notes", color: "green"), .init(number: 6, name: "web", color: "sky"),
        .init(number: 7, name: "media", color: "red"), .init(number: 8, name: "test", color: "gold"),
        .init(number: 9, name: "mail", color: "red"), .init(number: 10, name: "mac", color: "text"),
    ]
}

public struct BarWorkspace: Equatable, Sendable {
    public var number: Int
    public var color: String
    public var isActive: Bool
    public var appBundleIDs: [String]

    public init(number: Int, color: String, isActive: Bool, appBundleIDs: [String]) {
        self.number = number; self.color = color; self.isActive = isActive; self.appBundleIDs = appBundleIDs
    }
}

/// What the workspace part of a bar shows. Empty workspaces are hidden unless focused or visible.
public func barWorkspaces(state: HyprMacState, styles: [WorkspaceStyle], showEmpty: Bool) -> [BarWorkspace] {
    let byID = Dictionary(state.workspaces.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    return styles.compactMap { style in
        let ws = byID[style.number]
        let active = state.focusedWorkspace == style.number
        var apps: [String] = []
        for w in ws?.windows ?? [] where !w.bundleID.isEmpty && !apps.contains(w.bundleID) { apps.append(w.bundleID) }
        let show = showEmpty || active || ws?.visible == true || !(ws?.windows.isEmpty ?? true)
        return show ? BarWorkspace(number: style.number, color: style.color, isActive: active, appBundleIDs: apps) : nil
    }
}

/// One physical screen as AppKit sees it.
public struct ScreenSlot: Equatable, Sendable {
    public var displayID: UInt32
    public var localizedName: String
    public var originX: Double

    public init(displayID: UInt32, localizedName: String, originX: Double) {
        self.displayID = displayID
        self.localizedName = localizedName
        self.originX = originX
    }
}

/// Which `state.monitors` entry belongs to this screen. Monitors of one model share a name,
/// so same-name screens pair with same-name entries left to right.
public func monitorIndex(for slot: ScreenSlot, all: [ScreenSlot], stateMonitors: [Monitor]) -> Int? {
    let sameNameSlots = all.filter { $0.localizedName == slot.localizedName }.sorted { $0.originX < $1.originX }
    let sameNameEntries = stateMonitors.indices.filter { stateMonitors[$0].name == slot.localizedName }
    guard let pos = sameNameSlots.firstIndex(of: slot), pos < sameNameEntries.count else { return nil }
    return sameNameEntries[pos]
}

/// No tiling manager (HyprMac gone for a while, or never there): one desktop, like plain macOS, with every app
/// that has a Dock icon. Coloured as workspace 1.
public func singleDesktop(styles: [WorkspaceStyle], apps: [String]) -> [BarWorkspace] {
    [BarWorkspace(number: 1, color: styles.first { $0.number == 1 }?.color ?? "green", isActive: true, appBundleIDs: apps)]
}
