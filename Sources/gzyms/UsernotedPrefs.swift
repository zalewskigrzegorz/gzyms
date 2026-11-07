import CoreFoundation
import Foundation

private let usernotedContainer = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Group Containers/group.com.apple.usernoted").path

private typealias CopyWithContainer = @convention(c) (CFString, CFString, CFString, CFString, CFString?) -> Unmanaged<CFPropertyList>?
private typealias SyncWithContainer = @convention(c) (CFString, CFString?) -> Bool
/// Private CoreFoundation calls: nil once a macOS drops them, then only the file is read.
nonisolated(unsafe) private let cfprefsd: (copy: CopyWithContainer, sync: SyncWithContainer)? = {
    let h = dlopen(nil, RTLD_NOW)
    guard let c = dlsym(h, "_CFPreferencesCopyValueWithContainer"), let s = dlsym(h, "_CFPreferencesAppSynchronizeWithContainer") else { return nil }
    return (unsafeBitCast(c, to: CopyWithContainer.self), unsafeBitCast(s, to: SyncWithContainer.self))
}()

/// usernoted's notification prefs. macOS writes the file only about every 10 s, while cfprefsd has a click in System
/// Settings within 0.2 s (measured 2026-11-07). `live` takes the two keys Gzyms reads from cfprefsd.
/// nil = the file cannot be read (no Full Disk Access), and then cfprefsd is not asked either.
func usernotedPrefs(live: Bool) -> Data? {
    guard let file = try? Data(contentsOf: URL(filePath: usernotedContainer + "/Library/Preferences/group.com.apple.usernoted.plist")) else { return nil }
    guard live, let cfprefsd else { return file }
    let suite = "group.com.apple.usernoted" as CFString, dir = usernotedContainer as CFString
    _ = cfprefsd.sync(suite, dir)
    func value(_ key: String) -> Any? { cfprefsd.copy(key as CFString, suite, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, dir)?.takeRetainedValue() }
    guard let apps = value("apps") else { return file }
    var plist: [String: Any] = ["apps": apps]
    if let v = value("content_visibility") { plist["content_visibility"] = v }
    return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? file
}
