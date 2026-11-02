import AppKit
import GzymsCore

let dndName = Notification.Name("dev.gzyms.dnd")

/// `gzyms dnd on [minutes]|off`: Do Not Disturb from a script or a launcher, the same as the moon pill.
@MainActor
enum DNDCommand {
    static func run(_ args: [String]) -> Never {
        guard let message = dndMessage(args) else {
            FileHandle.standardError.write(Data("gzyms dnd: on [minutes] or off\n".utf8))
            exit(1)
        }
        guard barRunning() else {
            FileHandle.standardError.write(Data("gzyms dnd: Gzyms is not running\n".utf8))
            exit(1)
        }
        DistributedNotificationCenter.default().postNotificationName(dndName, object: message, userInfo: nil, deliverImmediately: true)
        exit(0)
    }

    /// A bar other than this command and the HUD (same bundle id).
    static func barRunning() -> Bool {
        let skip = [ProcessInfo.processInfo.processIdentifier, InstanceLock.holderPid(path: HUD.pidFile.path)]
        return NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").contains { !skip.contains($0.processIdentifier) }
    }
}
