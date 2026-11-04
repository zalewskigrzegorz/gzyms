/// Which banner elements in Notification Center's tree are new banners. The panel's history rows carry the same
/// subroles, and for ~0.2 s after `AXExpanded` turns false a closing panel still has them in the tree (spike: twelve
/// history rows taken for banners, then NC showed no banner until it was restarted). So nothing counts while the
/// panel is open and for `grace` seconds after it closes. Times are seconds of uptime.
public struct BannerFilter {
    public static let grace = 0.8
    /// Up when the observer attached (a "Login Items" alert): never published, never parked.
    public var skipPresentAtStart: Set<String> = []
    public private(set) var seen: Set<String> = []
    private var panelWasOpen = false
    private var closedAt = -Double.infinity

    public init() {}

    public mutating func note(panelOpen: Bool, now: Double) {
        if panelWasOpen, !panelOpen { closedAt = now }
        panelWasOpen = panelOpen
    }

    /// True once per uuid, for a banner outside the panel and its closing animation. Marks it seen.
    public mutating func accept(uuid: String, panelOpen: Bool, now: Double) -> Bool {
        note(panelOpen: panelOpen, now: now)
        guard !panelOpen, now - closedAt >= Self.grace, !skipPresentAtStart.contains(uuid), !seen.contains(uuid) else { return false }
        seen.insert(uuid)
        return true
    }
}
