import AppKit
import GzymsCore
import GzymsUI

let settingsName = Notification.Name("dev.gzyms.settings")
let meetingTestName = Notification.Name("dev.gzyms.meeting-test")
let messageName = Notification.Name("dev.gzyms.message")

/// `gzyms message whats-new|untested-macos`: debug only, shows that message from Gzyms now. Nothing is remembered.
@MainActor
enum MessageCommand {
    static let kinds = ["whats-new", "untested-macos"]
    static func run(_ kind: String?) -> Never {
        guard let kind, kinds.contains(kind) else {
            FileHandle.standardError.write(Data("usage: gzyms message \(kinds.joined(separator: "|"))\n".utf8))
            exit(1)
        }
        DistributedNotificationCenter.default().postNotificationName(messageName, object: kind, userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}

/// `gzyms meeting-test [minutes]`: a pretend meeting with a Meet link, starting in `minutes` (default 4), fed straight
/// into the reminders. Nothing is written to any calendar.
@MainActor
enum MeetingTestCommand {
    static func run(_ minutes: String?) -> Never {
        let m = minutes.flatMap(Double.init) ?? 4
        DistributedNotificationCenter.default().postNotificationName(meetingTestName, object: String(m), userInfo: nil, deliverImmediately: true)
        print("pretend meeting in \(m) min")
        exit(0)
    }
}

/// `gzyms settings [tab]`: opens (or closes) the settings panel of the running bar.
@MainActor
enum SettingsCommand {
    static func run(_ tab: String?) -> Never {
        if let tab, SettingsTab(rawValue: tab) == nil {
            FileHandle.standardError.write(Data("gzyms settings: no tab \"\(tab)\" (\(SettingsTab.allCases.map(\.rawValue).joined(separator: ", ")))\n".utf8))
            exit(1)
        }
        let skip = [ProcessInfo.processInfo.processIdentifier, InstanceLock.holderPid(path: HUD.pidFile.path)]
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").contains(where: { !skip.contains($0.processIdentifier) }) else {
            FileHandle.standardError.write(Data("gzyms settings: Gzyms is not running\n".utf8))
            exit(1)
        }
        DistributedNotificationCenter.default().postNotificationName(settingsName, object: tab ?? "", userInfo: nil, deliverImmediately: true)
        exit(0)
    }
}
