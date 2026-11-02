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
    func prefs(_ apps: [(String, Int)]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["apps": apps.map { ["bundle-id": $0.0, "flags": $0.1] }], format: .binary, options: 0)
    }
    let seen = ["com.chat", "com.mail", "com.ok"]
    // Flags as macOS 27 wrote them: the right setup, then Desktop and sound on, then everything off.
    let data = try prefs([("com.ok", 0x1280_3142), ("com.mail", 0x1280_314E), ("com.chat", 0x1280_3143), ("com.unseen", 0x1)])
    #expect(ncSettingsWarnings(prefs: data, apps: seen, hotkeys: nil) ==
            ["com.chat": "Notification Center off", "com.mail": "Desktop on, Sound on"])
    let off = try PropertyListSerialization.data(fromPropertyList: ["AppleSymbolicHotKeys": ["163": ["enabled": false]]], format: .binary, options: 0)
    #expect(ncSettingsWarnings(prefs: try prefs([("com.ok", 0x1280_3142)]), apps: seen, hotkeys: off) ==
            ["com.ok": "globe+N shortcut off"])
    #expect(ncSettingsWarnings(prefs: try prefs([("com.apple.mail", 0x1280_3142)]), apps: ["com.apple.mail"], hotkeys: nil) ==
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
