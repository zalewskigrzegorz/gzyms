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
                             link: ncLink(app: app, req: req), altLink: nil, sound: "message",
                             at: Date(timeIntervalSinceReferenceDate: delivered))
}

/// Where a click on another app's notification leads, built from what its record carries. nil = just open the app.
func ncLink(app: String, req: [String: Any]) -> String? {
    switch app {
    case "com.tinyspeck.slackmacgap": slackLink(req)
    default: nil
    }
}

/// Slack's record has no channel id and no thread, only `iden` = "<team id>_<message ts>" and the channel name as
/// the subtitle ("#name"; a DM has the sender's name there). `slack://channel` takes the name too (checked live).
private func slackLink(_ req: [String: Any]) -> String? {
    guard let iden = req["iden"] as? String, let m = iden.firstMatch(of: /^([TE][A-Z0-9]+)_/) else { return nil }
    var c = URLComponents()
    c.scheme = "slack"
    c.queryItems = [URLQueryItem(name: "team", value: String(m.1))]
    if let subt = req["subt"] as? String, subt.hasPrefix("#"), subt.count > 1, !subt.contains(" ") {
        c.host = "channel"
        c.queryItems?.append(URLQueryItem(name: "id", value: String(subt.dropFirst())))
    } else {
        c.host = "open"
    }
    return c.string
}

/// The app from a `usernoted` log line `Delivering <NotificationRecord app:"…" …> … updatedExisting: false`.
/// nil for anything else, and for updates of a notification already shown.
public func deliveredApp(_ message: String) -> String? {
    guard message.hasPrefix("Delivering <NotificationRecord"), !message.contains("updatedExisting: true"),
          let m = message.firstMatch(of: /app:"([^"]+)"/) else { return nil }
    return String(m.1)
}
