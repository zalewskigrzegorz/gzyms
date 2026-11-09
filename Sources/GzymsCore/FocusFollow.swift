import Foundation

/// Gzyms Do Not Disturb follows a macOS Focus: on when a Focus starts, off when it ends. It turns off only the DND
/// the Focus turned on, and any change by hand (moon pill, `gzyms dnd`, palette) takes it over.
/// shortcut: after a Gzyms restart during a Focus, the restored DND counts as set by hand and outlives the Focus;
/// persist `ownsDND` with the notes if that bites.
public struct FocusFollow {
    public enum Step: Equatable { case turnOn, turnOff }
    /// macOS's own Do Not Disturb Focus: the one followed when `[dnd] follow_focus` is not set.
    public static let dndMode = "com.apple.donotdisturb.mode.default"
    public private(set) var focusOn = false
    public private(set) var ownsDND = false

    public init() {}

    /// A fresh read of the Focus state; returns what to do with DND, if anything.
    public mutating func focus(_ on: Bool, dndOn: Bool) -> Step? {
        defer { focusOn = on }
        if on, !focusOn, !dndOn { ownsDND = true; return .turnOn }
        if !on, focusOn, ownsDND { ownsDND = false; return dndOn ? .turnOff : nil }
        return nil
    }

    public mutating func handSet() { ownsDND = false }
}

/// The mode ids of the Focuses on now, from `~/Library/DoNotDisturb/DB/Assertions.json`
/// (`storeAssertionRecords[].assertionDetails.assertionDetailsModeIdentifier`, seen on macOS 27.2).
public func activeFocusModes(assertions: Data) -> Set<String> {
    guard let root = try? JSONSerialization.jsonObject(with: assertions) as? [String: Any],
          let data = root["data"] as? [[String: Any]] else { return [] }
    return Set(data.flatMap { ($0["storeAssertionRecords"] as? [[String: Any]]) ?? [] }
        .compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String })
}

public struct FocusMode: Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// The Focuses set up on this Mac, by name, from `~/Library/DoNotDisturb/DB/ModeConfigurations.json`.
public func focusModes(modeConfigurations: Data) -> [FocusMode] {
    guard let root = try? JSONSerialization.jsonObject(with: modeConfigurations) as? [String: Any],
          let data = root["data"] as? [[String: Any]] else { return [] }
    return data.flatMap { (($0["modeConfigurations"] as? [String: [String: Any]]) ?? [:]).compactMap { id, c in
        ((c["mode"] as? [String: Any])?["name"] as? String).map { FocusMode(id: id, name: $0) }
    } }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
