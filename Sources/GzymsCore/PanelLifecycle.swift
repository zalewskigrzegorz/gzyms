import Foundation

public struct PanelActions: Equatable, Sendable {
    public var create: Set<UInt32>
    public var reshow: Set<UInt32>
    public var hide: Set<UInt32>
    public init(create: Set<UInt32>, reshow: Set<UInt32>, hide: Set<UInt32>) {
        self.create = create; self.reshow = reshow; self.hide = hide
    }
}

/// A display that disappears is only hidden at first. A slow monitor coming back after wake gets its own
/// panel back instead of a new one; the panel is destroyed only if the display stays gone past `grace`.
public struct PanelLifecycle: Sendable {
    public let grace: TimeInterval
    private var hiddenSince: [UInt32: TimeInterval] = [:]

    public init(grace: TimeInterval) { self.grace = grace }

    public mutating func apply(_ plan: DisplayPlan, at now: TimeInterval) -> PanelActions {
        for id in plan.destroy where hiddenSince[id] == nil { hiddenSince[id] = now }
        let reshow = plan.create.filter { hiddenSince[$0] != nil }
        reshow.forEach { hiddenSince[$0] = nil }
        return PanelActions(create: plan.create.subtracting(reshow), reshow: reshow, hide: plan.destroy)
    }

    /// Displays gone for longer than `grace`: destroy their panels now.
    public mutating func expire(at now: TimeInterval) -> Set<UInt32> {
        let gone = Set(hiddenSince.filter { now - $0.value >= grace }.keys)
        gone.forEach { hiddenSince[$0] = nil }
        return gone
    }
}

/// A crashed or quit HyprMac leaves its last state.json behind; it must not look live.
public func stateAfterAppExit(bundleID: String, current: StateRead) -> StateRead? {
    guard bundleID.hasPrefix("com.zachgray.HyprMac"), case let .fresh(s) = current else { return nil }
    return .stale(s, reason: "hyprmac quit")
}
