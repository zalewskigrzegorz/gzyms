import Foundation
import Testing
@testable import GzymsCore

private let uuid = "01234567-89AB-CDEF-0123-456789ABCDEF"

@Test func bannerBecomesNotificationWithTheDatabaseId() throws {
    let n = try #require(bannerNotification(axIdentifier: uuid,
        lines: BannerLines(app: "Slack", title: "Anna", subtitle: "#gzyms", body: "looks good"),
        app: "com.tinyspeck.slackmacgap", at: Date(timeIntervalSinceReferenceDate: 100)))
    // The database source reads `hex(r.uuid)`, which SQLite writes in upper case: the same id, so its row only overwrites.
    #expect(n.id == "nc-0123456789ABCDEF0123456789ABCDEF")
    #expect(ncRecordUUID(noteID: n.id) == uuid)
    #expect(n.title == "Anna")
    #expect(n.subtitle == "#gzyms")
    #expect(n.body == "looks good")
    #expect(n.app == "com.tinyspeck.slackmacgap")
    #expect(n.level == .info)
    #expect(n.sound == "message")
    #expect(n.link == nil)
    #expect(n.at == Date(timeIntervalSinceReferenceDate: 100))
}

@Test func bannerWithoutTitleUsesBodyAndEmptyIsNil() throws {
    let at = Date()
    let n = try #require(bannerNotification(axIdentifier: uuid.lowercased(), lines: BannerLines(app: "", title: "", subtitle: "", body: "x"), app: nil, at: at))
    #expect(n.title == "x")
    #expect(n.body == nil)
    #expect(n.subtitle == nil)
    #expect(n.app == nil)
    #expect(n.id == "nc-0123456789ABCDEF0123456789ABCDEF")
    #expect(bannerNotification(axIdentifier: uuid, lines: BannerLines(app: "Slack", title: "", subtitle: "s", body: ""), app: nil, at: at) == nil)
    #expect(bannerNotification(axIdentifier: "not-a-uuid", lines: BannerLines(app: "", title: "t", subtitle: "", body: ""), app: nil, at: at) == nil)
}

@Test func cleanStripsInvisibleMarks() {
    #expect(cleanAXString("\u{200E} WhatsApp ") == "WhatsApp")
    #expect(cleanAXString("a\u{200B}b") == "ab")
}
