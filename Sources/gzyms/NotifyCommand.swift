import AppKit
import GzymsCore

/// `gzyms notify --title …`: hand a notification to the running bar.
@MainActor
enum NotifyCommand {
    static func run(_ args: [String]) -> Never {
        let n: GzymsNotification
        switch parseNotify(args, now: Date()) {
        case .success(let ok): n = ok
        case .failure(let e): fail(e.message)
        }
        // The HUD shares the bundle id but does not listen.
        let skip = [ProcessInfo.processInfo.processIdentifier, InstanceLock.holderPid(path: HUD.pidFile.path)]
        let bars = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").filter { !skip.contains($0.processIdentifier) }
        if bars.isEmpty { fail("Gzyms is not running") }
        DistributedNotificationCenter.default().postNotificationName(notifyName, object: n.json, userInfo: nil, deliverImmediately: true)
        print(n.id)
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("gzyms notify: \(message)\n".utf8))
        exit(1)
    }
}
