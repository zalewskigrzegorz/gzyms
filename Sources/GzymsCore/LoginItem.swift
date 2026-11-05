/// `SMAppService.Status` of the main app as a login item, without importing ServiceManagement here.
public enum LoginItemStatus: Sendable {
    case notRegistered, enabled, requiresApproval, notFound
}

public enum LoginItemStep: Equatable, Sendable { case register, unregister, none }

/// What to do with the login item. `wanted` is `[bar] start_at_login`. `dev`: launchd's `dev.gzyms` (install-dev.sh)
/// already starts Gzyms at login, a login item would start a second one.
/// requiresApproval while wanted means the user turned it off in System Settings, so it stays theirs to turn back on.
public func loginItemStep(wanted: Bool, dev: Bool, status: LoginItemStatus) -> LoginItemStep {
    switch status {
    case .notRegistered: wanted && !dev ? .register : .none
    case .enabled, .requiresApproval: wanted && !dev ? .none : .unregister
    case .notFound: .none
    }
}
