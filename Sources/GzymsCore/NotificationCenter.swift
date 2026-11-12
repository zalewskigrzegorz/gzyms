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

/// Where the next database read starts: the newest delivery seen, but never later than `now` (both in seconds since
/// 2001). Calendar files a reminder at its event's time, hours ahead; as the start that hid every row until then
/// (live test 2026-11-04).
public func ncReadFrom(_ last: Double, delivered: Double, now: Double) -> Double { max(last, min(delivered, now)) }

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

/// One app's page in System Settings → Notifications, as far as Gzyms cares (Settings → Apps draws it).
public struct NCAppSettings: Equatable, Sendable {
    /// Allow notifications: off still files a row and logs the delivery, Gzyms drops both.
    public var allowed = true
    /// The Desktop tile: off means no banner to read.
    public var desktop = true
    /// Alert Style Persistent instead of Temporary.
    public var persistent = false
    /// The Notification Center tile: off means no row to press.
    public var center = true
    /// Play sound for notification: on means two sounds, macOS and Gzyms.
    public var sound = false
    /// Show previews: 0 = Default, 1 = Never, 2 = When Unlocked, 3 = Always.
    public var previews = 0
    /// The top of Notifications says Never, so Default hides the text too.
    public var defaultHidden = false
    /// The 🌐 N shortcut is off: no way to the panel. Not per app, but every app needs it.
    public var shortcutOff = false
    /// Mail: macOS lets nothing be set for it.
    public var unsupported = false
    /// A system agent System Settings does not list (BTMNotificationAgent): no page to open, nothing to change.
    public var hidden = false
    /// Its page has these rows only when the app asked for a badge or a sound (`auth`).
    public var hasBadge = true, hasSound = true
    /// An MDM profile sets its notifications: macOS greys out its page, so nobody can change it (issue #2).
    public var managed = false
    public init(allowed: Bool = true, desktop: Bool = true, persistent: Bool = false, center: Bool = true, sound: Bool = false, previews: Int = 0,
                defaultHidden: Bool = false, shortcutOff: Bool = false, unsupported: Bool = false, hasBadge: Bool = true, hasSound: Bool = true, hidden: Bool = false,
                managed: Bool = false) {
        self.allowed = allowed; self.desktop = desktop; self.persistent = persistent; self.center = center; self.sound = sound; self.previews = previews
        self.defaultHidden = defaultHidden; self.shortcutOff = shortcutOff; self.unsupported = unsupported
        self.hasBadge = hasBadge; self.hasSound = hasSound; self.hidden = hidden; self.managed = managed
    }

    public var previewsHidden: Bool { previews == 1 || (previews == 0 && defaultHidden) }
    /// Everything its own page can fix is set: the step-by-step setup moves on. The 🌐 N shortcut is not on that page.
    public var pageDone: Bool { unsupported || hidden || managed || (allowed && desktop && center && !sound && !previewsHidden) }
    /// What to change in macOS, in the order of its page. Empty = set up right.
    public var problems: [String] {
        if unsupported || hidden || managed { return [] }
        return [(!allowed, "Notifications off"), (!desktop, "Banners off"), (!center, "Notification Center off"), (previewsHidden, "Previews off"),
                (sound, "Sound on"), (shortcutOff, "🌐 N shortcut off")].filter(\.0).map(\.1)
    }
    public var warning: String? {
        if unsupported { return "macOS does not let you set notifications for Mail." }
        if managed { return "Your organization manages its notifications. Nothing to change." }
        return problems.isEmpty ? nil : problems.joined(separator: ", ")
    }
}

/// Per app, macOS's notification settings (`apps` in usernoted's group plist): what keeps Gzyms from reading its banner
/// or opening its original. Read by flipping the boxes live on macOS 27 (2026-11-04): `flags` 0x1 = Notification Center
/// off, 0x4 = Play sound on (Gzyms plays it), 0x8 = Desktop with Temporary banners, 0x10 = Desktop with Persistent alerts,
/// neither = Desktop off (no banner to read). `content_visibility` (Show previews): 0 = Default (the top-level value),
/// 1 = Never (a placeholder, no text), 2 = When Unlocked, 3 = Always. Lock Screen and the badge do not matter.
/// `auth` is what the app asked for (1 badge, 2 sound, 4 alert): without 2 its page has no sound switch, and 0x4 means nothing
/// (Xcode, `auth` 4, 2026-11-04). No `auth` = assume it can play one.
/// 0x02000000 = Allow notifications on (measured on Comet, then Calendar listed Off without it, 2026-11-04).
/// 0x01000000 = a system agent System Settings does not list (BTMNotificationAgent, tccd; no listed app has it).
/// Only `apps` (the ones Gzyms has seen) are read. nil = the settings could not be read.
/// `managed`: ids from `ncManagedApps`, matched whatever the case.
public func ncAppSettings(prefs: Data, apps: [String], hotkeys: Data?, managed: Set<String> = []) -> [String: NCAppSettings]? {
    guard let plist = try? PropertyListSerialization.propertyList(from: prefs, format: nil) as? [String: Any],
          let list = plist["apps"] as? [[String: Any]] else { return nil }
    // shortcut: an unset entry keeps the shortcut's default (on); an edited one says enabled = false.
    let keys = hotkeys.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    let entry = (keys?["AppleSymbolicHotKeys"] as? [String: Any])?["163"] as? [String: Any]
    let shortcutOff = entry?["enabled"] as? Bool == false
    let defaultHidden = plist["content_visibility"] as? Int == 1
    // macOS keeps some ids in another case than the app reports (com.apple.BTMNotificationAgent).
    let wanted = Dictionary(apps.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    var out: [String: NCAppSettings] = [:]
    for a in list {
        guard let raw = a["bundle-id"] as? String, let id = wanted[raw.lowercased()], let flags = a["flags"] as? Int else { continue }
        let auth = a["auth"] as? Int
        let hasSound = auth.map { $0 & 0x2 != 0 } ?? true
        out[id] = NCAppSettings(allowed: flags & 0x0200_0000 != 0, desktop: flags & 0x18 != 0, persistent: flags & 0x10 != 0, center: flags & 0x1 == 0,
                                sound: flags & 0x4 != 0 && hasSound, previews: a["content_visibility"] as? Int ?? 0, defaultHidden: defaultHidden,
                                shortcutOff: shortcutOff, unsupported: ncOpenOriginalUnsupported.contains(id),
                                hasBadge: auth.map { $0 & 0x1 != 0 } ?? true, hasSound: hasSound, hidden: flags & 0x0100_0000 != 0,
                                managed: managed.contains(raw.lowercased()))
    }
    return out
}

/// Where an MDM profile puts the apps whose notifications it sets. World-readable, no Full Disk Access needed.
public let ncManagedSettingsPath = "/Library/Managed Preferences/com.apple.notificationsettings.plist"

/// The bundle ids an MDM profile locks (`NotificationSettings[].BundleIdentifier`), lowercased. Empty when there is no profile.
public func ncManagedApps(_ data: Data?) -> Set<String> {
    guard let data, let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let list = plist["NotificationSettings"] as? [[String: Any]] else { return [] }
    return Set(list.compactMap { ($0["BundleIdentifier"] as? String)?.lowercased() })
}

/// The app from a `usernoted` log line `Delivering <NotificationRecord app:"…" …> … updatedExisting: false`.
/// nil for anything else, and for updates of a notification already shown.
public func deliveredApp(_ message: String) -> String? {
    guard message.hasPrefix("Delivering <NotificationRecord"), !message.contains("updatedExisting: true"),
          let m = message.firstMatch(of: /app:"([^"]+)"/) else { return nil }
    return String(m.1)
}
