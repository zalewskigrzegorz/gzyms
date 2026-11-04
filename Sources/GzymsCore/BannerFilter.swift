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

    public static let maxRetries = 25
    private var retries: [String: Int] = [:]

    public mutating func note(panelOpen: Bool, now: Double) {
        if panelWasOpen, !panelOpen { closedAt = now }
        panelWasOpen = panelOpen
    }

    /// The panel is open or still closing: no window may be moved now.
    public func closing(now: Double) -> Bool { panelWasOpen || now - closedAt < Self.grace }

    /// Another 20 ms try for a banner whose text is not there yet. After `maxRetries` it is left alone for good:
    /// its database row brings the text.
    public mutating func retry(uuid: String) -> Bool {
        let n = retries[uuid, default: 0] + 1
        retries[uuid] = n
        if n > Self.maxRetries { skipPresentAtStart.insert(uuid); retries[uuid] = nil; return false }
        return true
    }

    /// True once per uuid, for a banner outside the panel and its closing animation. Marks it seen.
    public mutating func accept(uuid: String, panelOpen: Bool, now: Double) -> Bool {
        note(panelOpen: panelOpen, now: now)
        guard !panelOpen, now - closedAt >= Self.grace, !skipPresentAtStart.contains(uuid), !seen.contains(uuid) else { return false }
        seen.insert(uuid)
        return true
    }
}
