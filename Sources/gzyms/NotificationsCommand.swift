import AppKit
import GzymsCore

let notificationsName = Notification.Name("dev.gzyms.notifications")

/// `gzyms notifications [--json] | dismiss <id> | clear`: what the bar holds, read from the file it writes after every
/// change (the HUD reads the same one). Listing works with the bar off; dismiss and clear go to the running bar.
@MainActor
enum NotificationsCommand {
    static var file: URL { VitalsWriter.url.deletingLastPathComponent().appendingPathComponent("notifications.json") }

    static func run(_ args: [String]) -> Never {
        let saved: NotificationStore.Saved
        do { saved = try NotificationStore.Saved.read(file) ?? .empty } catch { fail("gzyms notifications: \(file.path) does not read (\(error))") }
        switch (args.first, args.count) {
        case (nil, _): print(saved.text(now: Date()), terminator: "")
        case ("--json", 1): FileHandle.standardOutput.write(saved.json() + Data("\n".utf8))
        case ("dismiss", 2):
            guard saved.rows.contains(where: { $0.id == args[1] }) else { fail("gzyms notifications: no notification \"\(args[1])\"") }
            send("dismiss:\(args[1])")
        case ("clear", 1): send("clear")
        default: fail("usage: gzyms notifications [--json] | dismiss <id> | clear")
        }
        exit(0)
    }

    private static func send(_ message: String) {
        guard DNDCommand.barRunning() else { fail("gzyms notifications: Gzyms is not running") }
        DistributedNotificationCenter.default().postNotificationName(notificationsName, object: message, userInfo: nil, deliverImmediately: true)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
