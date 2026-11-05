import Foundation

/// Work that runs every frame or on a short timer until something stops it: a repeating animation, a timeline, a
/// polling timer. Each one signs in when it starts and out when it stops, and `gzyms debug cpu` lists who is in.
/// A SwiftUI view in a window that was only ordered out keeps animating and never sees onDisappear, so it stays
/// listed next to a hidden window: that pair is the bug (MacMirror's pulse, 2026-11-05).
public struct BusyRegistry: Equatable, Sendable {
    public private(set) var counts: [String: Int] = [:]
    public init() {}

    public mutating func start(_ name: String) { counts[name, default: 0] += 1 }

    public mutating func stop(_ name: String) {
        guard let n = counts[name] else { return }
        counts[name] = n > 1 ? n - 1 : nil
    }

    /// "name" or "name ×3", sorted.
    public var names: [String] { counts.keys.sorted().map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 } }
}

@MainActor public var busy = BusyRegistry()
