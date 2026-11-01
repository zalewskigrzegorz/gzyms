import Foundation

/// The macOS grants Gzyms needs. Each one is checked live; nothing is cached across launches.
public enum Grant: String, CaseIterable, Sendable {
    case accessibility, fullDiskAccess, calendars

    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .fullDiskAccess: "Full Disk Access"
        case .calendars: "Calendars"
        }
    }
    public var why: String {
        switch self {
        case .accessibility: "Dock badges and the banner keys"
        case .fullDiskAccess: "notifications from other apps. macOS applies a change here after Gzyms restarts."
        case .calendars: "meeting reminders. Add your accounts in Internet Accounts first."
        }
    }
    /// Without it Gzyms still runs; the setup wizard opens only for the required ones.
    public var required: Bool { self != .calendars }
    /// The System Settings page with the list to add Gzyms to.
    public var settingsURL: String {
        let page = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .calendars: "Privacy_Calendars"
        }
        return "x-apple.systempreferences:com.apple.preference.security?" + page
    }
}

public struct GrantState: Equatable, Sendable {
    public var grant: Grant
    public var granted: Bool
    public init(grant: Grant, granted: Bool) { self.grant = grant; self.granted = granted }
}

/// A grant that was on and is now off: the bar shows a quiet ⚠ instead of silently showing stale data.
/// A grant that was never given does not count; the wizard covers that.
public func revokedGrants(before: [GrantState], after: [GrantState]) -> [Grant] {
    after.filter { a in !a.granted && before.contains { $0.grant == a.grant && $0.granted } }.map(\.grant)
}
