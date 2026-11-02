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
