import Foundation
import GzymsCore
import ServiceManagement

/// install-dev.sh's LaunchAgent: it starts Gzyms at login and after a crash on Greg's Mac.
enum DevAgent {
    static let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/dev.gzyms.plist")
    /// The binary the job runs, symlinks resolved; nil without the plist.
    static var program: String? {
        guard let p = NSDictionary(contentsOf: plist), let program = (p["ProgramArguments"] as? [String])?.first else { return nil }
        return URL(fileURLWithPath: program).resolvingSymlinksInPath().path
    }
    static var me: String? { Bundle.main.executablePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } }
}

/// Gzyms as a login item (`SMAppService.mainApp`), for a release build installed from the tap.
enum LoginItem {
    /// launchd starts this Mac's Gzyms at login (install-dev.sh), or this is `swift run` with no bundle.
    static var dev: Bool {
        Bundle.main.bundleIdentifier == nil || FileManager.default.fileExists(atPath: DevAgent.plist.path)
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
