// Portions adapted from NotificationNanny (https://github.com/chessper53/NotificationNanny), MIT License, Copyright (c) 2026 chessper53
import Foundation

/// The labelled text of a macOS notification banner, read through Accessibility, already cleaned.
public struct BannerLines: Equatable, Sendable {
    public var app: String
    public var title: String
    public var subtitle: String
    public var body: String

    public init(app: String, title: String, subtitle: String, body: String) {
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}

/// A banner as a Gzyms notification. Its `AXIdentifier` is the record's uuid, so the id is the one the database row
/// gets ~5 s later (`hex(uuid)`, upper case) and that row only overwrites it. nil when the identifier is not a uuid or
/// there is no text yet. `app` nil = the app was not recognised from the banner's description.
public func bannerNotification(axIdentifier: String, lines: BannerLines, app bundleID: String?, at: Date) -> GzymsNotification? {
    guard let uuid = UUID(uuidString: axIdentifier) else { return nil }
    func text(_ s: String) -> String? { s.isEmpty ? nil : s }
    var title = text(lines.title), body = text(lines.body)
    if title == nil { title = body; body = nil }
    guard let title else { return nil }
    let hex = uuid.uuidString.replacingOccurrences(of: "-", with: "")
    return GzymsNotification(id: "nc-\(hex)", app: bundleID, level: .info, title: title, subtitle: text(lines.subtitle), body: body,
                             link: nil, altLink: nil, sound: "message", at: at)
}

/// Strips default-ignorable scalars (WhatsApp's U+200E) and trims. Nanny's `cleanAXString`.
public func cleanAXString(_ s: String) -> String {
    s.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }
        .reduce(into: "") { $0.append(Character($1)) }.trimmingCharacters(in: .whitespaces)
}
