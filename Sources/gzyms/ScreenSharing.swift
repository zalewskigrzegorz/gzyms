import CoreGraphics
import Foundation

/// Is anyone watching the screen: Zoom, Meet, Teams, QuickTime, a macOS screen share, or a mirrored display.
/// shortcut: macOS has no public call for capture (Apple forums 667549, FB14920414), so this reads the private
/// CGSIsScreenWatcherPresent; a DisplayLink adapter counts as a watcher too. nil = that call is gone in this macOS.
enum ScreenSharing {
    private typealias WatcherFn = @convention(c) () -> Bool
    private static let watcher = dlsym(dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
                                       "CGSIsScreenWatcherPresent").map { unsafeBitCast($0, to: WatcherFn.self) }

    static func now() -> Bool? {
        if CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0 { return true }
        return watcher?()
    }
}
