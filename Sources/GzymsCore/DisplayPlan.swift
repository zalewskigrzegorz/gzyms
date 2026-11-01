/// Which bar panels to keep, create and destroy when the set of screens changes.
public struct DisplayPlan: Equatable, Sendable {
    public var keep: Set<UInt32>
    public var create: Set<UInt32>
    public var destroy: Set<UInt32>

    public init(keep: Set<UInt32>, create: Set<UInt32>, destroy: Set<UInt32>) {
        self.keep = keep
        self.create = create
        self.destroy = destroy
    }

    public var changesNothing: Bool { create.isEmpty && destroy.isEmpty }
}

/// Panels whose display id survives are kept as they are. An empty screen list (seen for a moment
/// during wake) is never a reason to tear everything down.
public func planDisplays(current: Set<UInt32>, next: Set<UInt32>) -> DisplayPlan {
    guard !next.isEmpty else { return DisplayPlan(keep: current, create: [], destroy: []) }
    return DisplayPlan(keep: current.intersection(next), create: next.subtracting(current), destroy: current.subtracting(next))
}
