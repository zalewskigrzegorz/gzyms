import Foundation

/// HyprMac's `state.json` (see HyprMac `docs/status-bar.md`). Unknown keys are ignored.
public struct HyprMacState: Equatable, Sendable, Decodable {
    public var focusedWorkspace: Int?
    public var focusedMonitor: String?
    public var monitors: [Monitor]
    public var workspaces: [Workspace]

    public init(focusedWorkspace: Int?, focusedMonitor: String?, monitors: [Monitor], workspaces: [Workspace]) {
        self.focusedWorkspace = focusedWorkspace
        self.focusedMonitor = focusedMonitor
        self.monitors = monitors
        self.workspaces = workspaces
    }
}

public struct Monitor: Equatable, Sendable, Decodable {
    public var name: String
    public var visibleWorkspace: Int
    public var focused: Bool
}

public struct Workspace: Equatable, Sendable, Decodable {
    public var id: Int
    public var name: String?
    public var monitor: String
    public var visible: Bool
    public var windows: [Window]
    /// What the bar prints instead of the number: AeroSpace's workspace name, also what its switch command takes. Not in HyprMac's file.
    public var label: String? = nil
}

public struct Window: Equatable, Sendable, Decodable {
    public var id: Int
    public var app: String
    /// Empty when HyprMac has none (java, wine, "Unknown app"): HyprMac leaves the key out.
    public var bundleID: String
    public var floating: Bool
    public var focused: Bool
}

// Lenient decoding: one odd entry is dropped, never the whole file (HyprMac omits nil keys).
// In extensions so the memberwise initialisers stay.
extension HyprMacState {
    private enum Keys: String, CodingKey { case focusedWorkspace, focusedMonitor, monitors, workspaces }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        focusedWorkspace = try? c.decodeIfPresent(Int.self, forKey: .focusedWorkspace)
        focusedMonitor = try? c.decodeIfPresent(String.self, forKey: .focusedMonitor)
        monitors = (try c.decodeIfPresent([Lenient<Monitor>].self, forKey: .monitors) ?? []).compactMap(\.value)
        workspaces = (try c.decodeIfPresent([Lenient<Workspace>].self, forKey: .workspaces) ?? []).compactMap(\.value)
    }
}

extension Workspace {
    private enum Keys: String, CodingKey { case id, name, monitor, visible, windows }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        monitor = (try? c.decodeIfPresent(String.self, forKey: .monitor)) ?? ""
        visible = (try? c.decodeIfPresent(Bool.self, forKey: .visible)) ?? false
        windows = ((try? c.decodeIfPresent([Lenient<Window>].self, forKey: .windows)) ?? []).compactMap(\.value)
    }
}

extension Window {
    private enum Keys: String, CodingKey { case id, app, bundleID, floating, focused }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        app = (try? c.decodeIfPresent(String.self, forKey: .app)) ?? ""
        bundleID = (try? c.decodeIfPresent(String.self, forKey: .bundleID)) ?? ""
        floating = (try? c.decodeIfPresent(Bool.self, forKey: .floating)) ?? false
        focused = (try? c.decodeIfPresent(Bool.self, forKey: .focused)) ?? false
    }
}

struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

public enum StateRead: Equatable, Sendable {
    case fresh(HyprMacState)
    case stale(HyprMacState, reason: String)
    case none
}

/// A missing or broken file never blanks the bar: the last good state comes back marked stale.
public func readState(_ data: Data?, previous: HyprMacState?) -> StateRead {
    guard let data else { return previous.map { .stale($0, reason: "missing") } ?? .none }
    guard var state = try? JSONDecoder().decode(HyprMacState.self, from: data) else {
        return previous.map { .stale($0, reason: "decode") } ?? .none
    }
    state.workspaces.removeAll { !(1...10).contains($0.id) }
    return .fresh(state)
}
