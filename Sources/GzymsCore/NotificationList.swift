import Foundation

/// One line of `gzyms notifications` and of the HUD's Queues tab, both read from notifications.json.
public struct NotificationRow: Codable, Equatable, Identifiable, Sendable {
    /// `stack`: on screen (position 1) or waiting in the stack. `waiting`: no room in the stack yet, comes up in order.
    /// `missed`: came during a quiet period (locked, asleep, Do Not Disturb, sharing), never in an app's list.
    public enum Place: String, Codable, Sendable { case stack, waiting, list, missed, snoozed }
    public var id: String
    /// The app's bundle id, `plugin:<folder>`, `meeting`, or `bell` (no app: the 🔔).
    public var source: String
    public var level: NotifyLevel
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var at: Date
    public var place: Place
    /// From 1 within its place; nil in a list.
    public var position: Int?
    /// Its sound played already. Only in the stack and waiting.
    public var heard: Bool?
    /// When a snoozed one comes back.
    public var back: Date?
}

public func notificationSource(_ n: GzymsNotification) -> String {
    n.meetingStart != nil ? "meeting" : ruleKey(n) ?? "bell"
}

extension NotificationStore.Saved {
    /// No file yet: the bar never ran.
    public static let empty = Self(inbox: [], snoozed: [])

    /// The stack, then the ones waiting, the lists and the missed list (newest first) and the snoozed (soonest back first).
    public var rows: [NotificationRow] {
        func row(_ n: GzymsNotification, _ place: NotificationRow.Place, _ position: Int?, heard: Bool? = nil, back: Date? = nil) -> NotificationRow {
            NotificationRow(id: n.id, source: notificationSource(n), level: n.level, title: n.title, subtitle: n.subtitle, body: n.body,
                            at: n.at, place: place, position: position, heard: heard, back: back)
        }
        let live = self.live ?? []
        let stack = live.filter { !$0.waiting }, waiting = live.filter(\.waiting)
        let ids = Set(live.map(\.n.id))
        return stack.enumerated().map { row($1.n, .stack, $0 + 1, heard: $1.heard) }
            + waiting.enumerated().map { row($1.n, .waiting, $0 + 1, heard: $1.heard) }
            + inbox.filter { !ids.contains($0.id) }.sorted { $0.at > $1.at }.map { row($0, .list, nil) }
            + (missed ?? []).map { row($0, .missed, nil) }
            + snoozed.sorted { $0.at < $1.at }.enumerated().map { row($1.n, .snoozed, $0 + 1, back: $1.at) }
    }

    /// `gzyms notifications --json`: every field in full.
    public func json() -> Data {
        struct Out: Encodable { var dnd: Date?; var notifications: [NotificationRow] }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return (try? e.encode(Out(dnd: dnd, notifications: rows))) ?? Data("{}".utf8)
    }

    /// `gzyms notifications`: grouped by place, the text cut to one short line.
    public func text(now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        func time(_ d: Date) -> String {
            f.dateFormat = calendar.isDate(d, inSameDayAs: now) ? "HH:mm" : "yyyy-MM-dd HH:mm"
            return f.string(from: d)
        }
        func line(_ r: NotificationRow) -> String {
            var text = [r.title, r.subtitle, r.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                .replacingOccurrences(of: "\n", with: " ")
            if text.count > 70 { text = text.prefix(69) + "…" }
            let pos = r.position.map { String($0).padding(toLength: 3, withPad: " ", startingAt: 0) } ?? ""
            let extra = (r.heard == true ? "  heard" : "") + (r.back.map { "  back \(time($0))" } ?? "")
            return "  \(pos)\(r.level.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0))\(time(r.at))  \(r.source)  \(text)  [\(r.id)]\(extra)"
        }
        let all = rows
        var out = dnd.map { $0 == .distantFuture ? "Do not disturb: on\n\n" : "Do not disturb: on until \(time($0))\n\n" } ?? ""
        guard !all.isEmpty else { return out + "No notifications.\n" }
        let groups: [(NotificationRow.Place, String)] = [(.stack, "Stack, 1 is on screen"), (.waiting, "Waiting for room in the stack"),
                                                        (.list, "In the lists"), (.missed, "Missed while you were away"), (.snoozed, "Snoozed")]
        out += groups.compactMap { place, name in
            let g = all.filter { $0.place == place }
            return g.isEmpty ? nil : "\(name) (\(g.count)):\n" + g.map(line).joined(separator: "\n") + "\n"
        }.joined(separator: "\n")
        return out
    }
}
