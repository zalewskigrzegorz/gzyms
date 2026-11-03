import Foundation

/// The distributed notification `gzyms notify` posts; its object is the notification as JSON.
public let notifyName = Notification.Name("dev.gzyms.notify")

public struct NotifyArgsError: Error, Equatable {
    public let message: String
}

/// The flags `gzyms notify` takes with a value. skill/guide.md documents each one (SkillTests checks).
public let notifyFlags = ["--title", "--subtitle", "--body", "--level", "--id", "--app", "--link", "--alt-link", "--alt-label", "--sound", "--screen"]
/// The flags `gzyms notify` takes alone.
public let notifySwitches = ["--compact", "--reminder"]
/// One letter where it is free (Greg): --sound and --screen share s with --subtitle, --link and --alt-link lose to
/// --level and --app, so those four have none.
public let notifyShort = ["-t": "--title", "-s": "--subtitle", "-b": "--body", "-l": "--level", "-i": "--id", "-a": "--app",
                          "-c": "--compact", "-r": "--reminder"]

/// `gzyms notify --title … [--subtitle --body --level --id --app --link --alt-link --alt-label --sound --screen] [--compact] [--reminder]`.
/// `--compact` is the small island with only the app's icon, `--reminder` stays until acted on.
public func parseNotify(_ args: [String], now: Date) -> Result<GzymsNotification, NotifyArgsError> {
    let known = notifyFlags, switches = notifySwitches
    var v: [String: String] = [:]
    var on = Set<String>()
    var rest = args[...]
    while let typed = rest.popFirst() {
        let flag = notifyShort[typed] ?? typed
        if switches.contains(flag) { on.insert(flag); continue }
        guard known.contains(flag) else { return .failure(.init(message: "unknown flag \(flag) (known: \((known + switches).map(withShort).joined(separator: " ")))")) }
        guard let value = rest.popFirst() else { return .failure(.init(message: "\(typed) needs a value")) }
        v[flag] = value
    }
    // The compact island draws no text, so it needs no title; it needs the app whose icon it shows.
    if on.contains("--compact"), v["--app"] == nil { return .failure(.init(message: "--compact needs --app <bundle id>, its icon is all it shows")) }
    guard let title = v["--title"] ?? (on.contains("--compact") ? "" : nil) else { return .failure(.init(message: "--title is required")) }
    var level = NotifyLevel.info
    if let raw = v["--level"] {
        guard let l = NotifyLevel(rawValue: raw) else {
            let levels = NotifyLevel.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(.init(message: "no level \"\(raw)\" (levels: \(levels))"))
        }
        level = l
    }
    var n = GzymsNotification(id: v["--id"] ?? UUID().uuidString, app: v["--app"], level: level, title: title,
                              subtitle: v["--subtitle"], body: v["--body"], link: v["--link"], altLink: v["--alt-link"],
                              sound: v["--sound"], at: now, reminder: on.contains("--reminder"), screen: v["--screen"])
    n.compact = on.contains("--compact")
    n.altLabel = v["--alt-label"]
    return .success(n)
}

/// "--title" → "-t/--title", a flag without a short form stays as it is.
public func withShort(_ flag: String) -> String {
    notifyShort.first { $0.value == flag }.map { "\($0.key)/\(flag)" } ?? flag
}

/// `gzyms set <key> <value>`: the dotted key as in config.toml, with the last part the key itself.
/// `appearance.animations` → (["appearance"], "animations"); `notifications.apps."com.x".banner` keeps the quoted part whole.
public func configKey(_ dotted: String) -> (table: [String], key: String)? {
    let parts = splitDotted(dotted)
    guard let key = parts.last, !key.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }
    return (Array(parts.dropLast()), key)
}

/// A value typed on the command line: true/false, a whole or decimal number, `[a, b]` or `[1, 2]`, else text.
public func tomlValue(cli s: String) -> TOMLValue {
    if s == "true" || s == "false" { return .bool(s == "true") }
    if let i = Int(s) { return .int(i) }
    if let d = Double(s), s.contains(".") { return .double(d) }
    if s.hasPrefix("["), s.hasSuffix("]") {
        let items = s.dropFirst().dropLast().split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        let ints = items.compactMap { Int($0) }
        return ints.count == items.count && !items.isEmpty ? .ints(ints) : .strings(items)
    }
    return .string(s)
}

extension GzymsNotification {
    public var json: String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }

    public init?(json: String) {
        guard let n = try? JSONDecoder().decode(GzymsNotification.self, from: Data(json.utf8)) else { return nil }
        self = n
    }
}

