import Foundation

/// One row of macOS's Notification Center database as a Gzyms notification. The row's `data` is a binary plist
/// with the text under `req` (spike S1). nil when there is nothing to show.
/// `key` is the record's uuid: row numbers are reused once an app removes its notifications.
public func ncNotification(key: String, app: String, delivered: Double, data: Data) -> GzymsNotification? {
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let req = plist["req"] as? [String: Any] else { return nil }
    func text(_ key: String) -> String? { (req[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    var title = text("titl"), body = text("body")
    if title == nil { title = body; body = nil }
    guard let title else { return nil }
    return GzymsNotification(id: "nc-\(key)", app: app, level: .info, title: title, subtitle: text("subt"), body: body,
                             link: nil, altLink: nil, sound: "message", at: Date(timeIntervalSinceReferenceDate: delivered))
}

/// The record's uuid as Notification Center's own panel names the banner (its AX identifier), from a note's id.
/// nil for notes that did not come from the database.
public func ncRecordUUID(noteID: String) -> String? {
    let hex = Array(noteID.dropFirst(3))
    guard noteID.hasPrefix("nc-"), hex.count == 32 else { return nil }
    let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
    return UUID(uuidString: parts.joined(separator: "-"))?.uuidString
}

/// Apps whose original cannot be opened this way (Greg, 2026-11-02: Mail cannot be set up for it): a click opens just the app.
public let ncOpenOriginalUnsupported: Set<String> = ["com.apple.mail"]

/// Per app, what keeps opening the original in Notification Center from working (the warning sign in Settings → Apps),
/// from macOS's per-app notification settings (`apps` in usernoted's group plist). `flags` read by flipping the boxes
/// live on macOS 27: 0x1 = Notification Center off, 0x4 = Play sound on (Gzyms plays it), 0x8 = Desktop on.
/// Lock Screen and the badge do not matter.
/// Only `apps` (the ones Gzyms has seen) are checked. nil = the settings could not be read.
public func ncSettingsWarnings(prefs: Data, apps: [String], hotkeys: Data?) -> [String: String]? {
    guard let plist = try? PropertyListSerialization.propertyList(from: prefs, format: nil) as? [String: Any],
          let list = plist["apps"] as? [[String: Any]] else { return nil }
    // shortcut: an unset entry keeps the shortcut's default (on); an edited one says enabled = false.
    let keys = hotkeys.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    let entry = (keys?["AppleSymbolicHotKeys"] as? [String: Any])?["163"] as? [String: Any]
    let shortcutOff = entry?["enabled"] as? Bool == false
    var out: [String: String] = [:]
    for a in list {
        guard let id = a["bundle-id"] as? String, apps.contains(id), let flags = a["flags"] as? Int else { continue }
        if ncOpenOriginalUnsupported.contains(id) { out[id] = "macOS does not let you set notifications for Mail."; continue }
        var wrong: [String] = []
        if flags & 0x1 != 0 { wrong.append("Notification Center off") }
        if flags & 0x8 != 0 { wrong.append("Desktop on") }
        if flags & 0x4 != 0 { wrong.append("Sound on") }
        if shortcutOff { wrong.append("globe+N shortcut off") }
        if !wrong.isEmpty { out[id] = wrong.joined(separator: ", ") }
    }
    return out
}

/// The app from a `usernoted` log line `Delivering <NotificationRecord app:"…" …> … updatedExisting: false`.
/// nil for anything else, and for updates of a notification already shown.
public func deliveredApp(_ message: String) -> String? {
    guard message.hasPrefix("Delivering <NotificationRecord"), !message.contains("updatedExisting: true"),
          let m = message.firstMatch(of: /app:"([^"]+)"/) else { return nil }
    return String(m.1)
}
