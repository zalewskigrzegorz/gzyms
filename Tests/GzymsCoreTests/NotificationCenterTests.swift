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
    func warnings(_ prefs: Data, _ apps: [String]? = nil, hotkeys: Data? = nil) -> [String: String]? {
        ncAppSettings(prefs: prefs, apps: apps ?? seen, hotkeys: hotkeys)?.compactMapValues(\.warning)
    }
    #expect(warnings(data) ==
            ["com.none": "Banners off", "com.nc": "Notification Center off", "com.sound": "Sound on", "com.never": "Previews off",
             "com.global": "Previews off", "com.default": "Previews off", "com.two": "Banners off, Sound on"])
    #expect(warnings(try prefs([("com.global", banners, nil)], global: 2)) == [:])
    let off = try PropertyListSerialization.data(fromPropertyList: ["AppleSymbolicHotKeys": ["163": ["enabled": false]]], format: .binary, options: 0)
    #expect(warnings(try prefs([("com.ok", banners, 3)]), hotkeys: off) == ["com.ok": "globe+N shortcut off"])
    #expect(warnings(try prefs([("com.apple.mail", banners, 3)]), ["com.apple.mail"]) ==
            ["com.apple.mail": "macOS does not let you set notifications for Mail."])
    #expect(warnings(Data("nope".utf8)) == nil)
    // The mirror needs the tiles as they are, not just what is wrong.
    let spark = try #require(ncAppSettings(prefs: try prefs([("com.spark", 0x0200_0000 | 0x10 | 0x1, 2)]), apps: ["com.spark"], hotkeys: nil)?["com.spark"])
    #expect(spark == NCAppSettings(desktop: true, persistent: true, center: false, sound: false, previews: 2))
    #expect(NCAppSettings(shortcutOff: true).pageDone && !NCAppSettings(sound: true).pageDone)
    #expect(!NCAppSettings(defaultHidden: true).pageDone && NCAppSettings(previews: 2, defaultHidden: true).pageDone)
    // Allow notifications off: neither 0x02000000 nor Apple's 0x10000000 (Comet with it off, then on).
    let comet = try PropertyListSerialization.data(fromPropertyList: ["apps": [["bundle-id": "c.off", "flags": 0x0080_204A],
                                                                                ["bundle-id": "c.on", "flags": 0x0280_204A],
                                                                                ["bundle-id": "apple", "flags": 0x3088_0012]]],
                                                   format: .binary, options: 0)
    #expect(ncAppSettings(prefs: comet, apps: ["c.off", "c.on", "apple"], hotkeys: nil)?.compactMapValues(\.warning) == ["c.off": "Notifications off"])
    // An app that never asked for sound has no sound switch: its 0x4 is no warning (Xcode, auth 4).
    let xcode = try PropertyListSerialization.data(fromPropertyList: ["apps": [["bundle-id": "com.x", "flags": 0x1280200e, "auth": 4],
                                                                                ["bundle-id": "com.m", "flags": 0x1280200e, "auth": 7]]],
                                                   format: .binary, options: 0)
    #expect(ncAppSettings(prefs: xcode, apps: ["com.x", "com.m"], hotkeys: nil)?.mapValues(\.sound) == ["com.x": false, "com.m": true])
    #expect(ncAppSettings(prefs: xcode, apps: ["com.x"], hotkeys: nil)?["com.x"].map { [$0.hasBadge, $0.hasSound] } == [false, false])
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
