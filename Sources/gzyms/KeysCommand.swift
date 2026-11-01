import AppKit
import GzymsCore

let keysName = Notification.Name("dev.gzyms.keys")

/// `gzyms keys on|off`: the keyboard mode from outside (a launcher, a script, when the leader is taken).
@MainActor
enum KeysCommand {
    static func run(_ arg: String?) -> Never {
        guard let arg, ["on", "off"].contains(arg) else {
            FileHandle.standardError.write(Data("gzyms keys: on or off\n".utf8))
            exit(1)
        }
        let skip = [ProcessInfo.processInfo.processIdentifier, InstanceLock.holderPid(path: HUD.pidFile.path)]
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").contains(where: { !skip.contains($0.processIdentifier) }) else {
            FileHandle.standardError.write(Data("gzyms keys: Gzyms is not running\n".utf8))
            exit(1)
        }
        DistributedNotificationCenter.default().postNotificationName(keysName, object: arg, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}
