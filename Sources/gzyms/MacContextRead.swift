import CoreGraphics
import Foundation
import GzymsCore

extension MacContext {
    /// CoreGraphics and one file read, no AppKit: the watchdog calls it off main, while main is the one hung.
    static func read() -> MacContext {
        var c = MacContext()
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        c.screenLocked = session?["CGSSessionScreenIsLocked"] as? Bool == true
        let main = CGMainDisplayID()
        c.displayAsleep = CGDisplayIsAsleep(main) != 0
        let assertions = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/DoNotDisturb/DB/Assertions.json")
        c.focusOn = (try? Data(contentsOf: assertions)).map(focusIsOn(assertions:)) ?? false
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        // Online, not active: a sleeping screen is still listed.
        if CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success {
            c.screens = ids.prefix(Int(count)).map {
                screen(builtin: CGDisplayIsBuiltin($0) != 0, width: CGDisplayPixelsWide($0), height: CGDisplayPixelsHigh($0), main: $0 == main)
            }
        }
        return c
    }
}
