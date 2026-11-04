import Foundation
import Testing
@testable import GzymsCore

private func blob(_ req: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: ["app": "com.tinyspeck.slackmacgap", "req": req], format: .binary, options: 0)
}

@Test func recordBecomesNotification() throws {
    let data = try blob(["titl": "Anna", "subt": "#gzyms", "body": "looks good"])
    let n = try #require(ncNotification(key: "42", app: "com.tinyspeck.slackmacgap", delivered: 100, data: data))
    #expect(n.id == "nc-42")
    #expect(n.app == "com.tinyspeck.slackmacgap")
    #expect(n.title == "Anna")
    #expect(n.subtitle == "#gzyms")
    #expect(n.body == "looks good")
    #expect(n.level == .info)
    #expect(n.at == Date(timeIntervalSinceReferenceDate: 100))
    #expect(soundSource(for: n, choices: [:]) == .system("Pop"))  // macOS banners are off for these apps, so Gzyms plays the sound
    #expect(soundSource(for: .pending(app: "com.app", at: n.at), choices: [:]) == .system("Pop"))
}

@Test func noteIDGivesThePanelsBannerID() {
    #expect(ncRecordUUID(noteID: "nc-0123456789ABCDEF0123456789ABCDEF") == "01234567-89AB-CDEF-0123-456789ABCDEF")
    #expect(ncRecordUUID(noteID: "nc-0123456789abcdef0123456789abcdef") == "01234567-89AB-CDEF-0123-456789ABCDEF")
    #expect(ncRecordUUID(noteID: "pending-com.tinyspeck.slackmacgap") == nil)
    #expect(ncRecordUUID(noteID: "nc-42") == nil)
    #expect(ncRecordUUID(noteID: "nc-0123456789ABCDEF0123456789ABCDEZ") == nil)
}

@Test func settingsWarnAboutWhatIsWrong() throws {
    /// (bundle id, flags, per-app content_visibility or nil = follows the global one).
    func prefs(_ apps: [(String, Int, Int?)], global: Int = 3) throws -> Data {
        let list = apps.map { a -> [String: Any] in
            var d: [String: Any] = ["bundle-id": a.0, "flags": a.1]
            if let v = a.2 { d["content_visibility"] = v }
            return d
        }
        return try PropertyListSerialization.data(fromPropertyList: ["apps": list, "content_visibility": global], format: .binary, options: 0)
    }
    // content_visibility: 0 Default (the global one), 1 Never, 2 When Unlocked, 3 Always.
    // Flags as macOS 27 wrote them for Script Editor (2026-11-04): 0x8 Temporary, 0x10 Persistent, neither = Desktop off.
    let banners = 0x0280_204A, alerts = 0x0280_2052, none = 0x0280_2042
    let seen = ["com.ok", "com.alerts", "com.none", "com.nc", "com.sound", "com.never", "com.global", "com.default", "com.two"]
    let data = try prefs([("com.ok", banners, 3), ("com.alerts", alerts, 2), ("com.none", none, 3), ("com.nc", banners | 0x1, 3),
                          ("com.sound", banners | 0x4, 3), ("com.never", banners, 1), ("com.global", banners, nil), ("com.default", banners, 0),
                          ("com.two", none | 0x4, 3), ("com.unseen", none, 1)], global: 1)
    #expect(ncSettingsWarnings(prefs: data, apps: seen, hotkeys: nil) ==
            ["com.none": "Banners off", "com.nc": "Notification Center off", "com.sound": "Sound on", "com.never": "Previews off",
             "com.global": "Previews off", "com.default": "Previews off", "com.two": "Banners off, Sound on"])
    #expect(ncSettingsWarnings(prefs: try prefs([("com.global", banners, nil)], global: 2), apps: seen, hotkeys: nil) == [:])
    let off = try PropertyListSerialization.data(fromPropertyList: ["AppleSymbolicHotKeys": ["163": ["enabled": false]]], format: .binary, options: 0)
    #expect(ncSettingsWarnings(prefs: try prefs([("com.ok", banners, 3)]), apps: seen, hotkeys: off) == ["com.ok": "globe+N shortcut off"])
    #expect(ncSettingsWarnings(prefs: try prefs([("com.apple.mail", banners, 3)]), apps: ["com.apple.mail"], hotkeys: nil) ==
            ["com.apple.mail": "macOS does not let you set notifications for Mail."])
    #expect(ncSettingsWarnings(prefs: Data("nope".utf8), apps: seen, hotkeys: nil) == nil)
}

@Test func recordWithoutTitleUsesBody() throws {
    let n = try #require(ncNotification(key: "1", app: "com.x", delivered: 0, data: try blob(["body": "only body"])))
    #expect(n.title == "only body")
    #expect(n.body == nil)
}

@Test func emptyOrBrokenRecordIsSkipped() throws {
    #expect(ncNotification(key: "1", app: "com.x", delivered: 0, data: try blob([:])) == nil)
    #expect(ncNotification(key: "1", app: "com.x", delivered: 0, data: Data("nope".utf8)) == nil)
}

@Test func deliveringLineGivesTheApp() {
    let line = #"Delivering <NotificationRecord app:"com.apple.ScriptEditor2" ident:"DA39-A3EE" req:"" uuid:"446461C4"> to [ .alert ]: updatedExisting: false"#
    #expect(deliveredApp(line) == "com.apple.ScriptEditor2")
    #expect(deliveredApp(line.replacingOccurrences(of: "updatedExisting: false", with: "updatedExisting: true")) == nil)
    #expect(deliveredApp("Removing something") == nil)
}
