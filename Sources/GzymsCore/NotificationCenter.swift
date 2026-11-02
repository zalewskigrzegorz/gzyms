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

/// The app from a `usernoted` log line `Delivering <NotificationRecord app:"…" …> … updatedExisting: false`.
/// nil for anything else, and for updates of a notification already shown.
public func deliveredApp(_ message: String) -> String? {
    guard message.hasPrefix("Delivering <NotificationRecord"), !message.contains("updatedExisting: true"),
          let m = message.firstMatch(of: /app:"([^"]+)"/) else { return nil }
    return String(m.1)
}
