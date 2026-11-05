import Foundation
import GzymsCore
import ServiceManagement

/// Gzyms as a login item (`SMAppService.mainApp`), for a release build installed from the tap.
enum LoginItem {
    /// launchd starts this Mac's Gzyms at login (install-dev.sh), or this is `swift run` with no bundle.
    static var dev: Bool {
        Bundle.main.bundleIdentifier == nil || FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/dev.gzyms.plist").path)
    }

    static var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        default: .notFound
        }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// On launch and after every config change: makes macOS match `[bar] start_at_login`.
    static func sync(wanted: Bool) {
        let step = loginItemStep(wanted: wanted, dev: dev, status: status)
        do {
            switch step {
            case .register: try SMAppService.mainApp.register()
            case .unregister: try SMAppService.mainApp.unregister()
            case .none: return
            }
            log("login item: \(step)ed")
        } catch { log("login item: \(step) failed: \(error.localizedDescription)") }
    }
}
