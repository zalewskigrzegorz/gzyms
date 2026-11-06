import Foundation
import TOMLDecoder

/// `plugin.toml`: what a plugin folder says about itself.
public struct PluginManifest: Equatable, Sendable {
    /// The folder's name: the id in config (`[plugins.<folder>]`) and on the CLI.
    public var folder: String
    public var name: String
    /// Run with `/bin/sh -c` inside the folder.
    public var command: String
    public var description: String
    public var icon: String?
    /// The settings it declares (`[[option]]`); Settings draws a form from them, no UI code in the plugin.
    public var options: [PluginOption]

    public init(folder: String, name: String, command: String, description: String = "", icon: String? = nil, options: [PluginOption] = []) {
        self.folder = folder; self.name = name; self.command = command; self.description = description; self.icon = icon
        self.options = options
    }
}

/// One `[[option]]` of a manifest. The value lives in config.toml as `[plugins.<folder>] <key> = …`.
public struct PluginOption: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case toggle, choice, text, number, list }
    public var key: String, title: String, kind: Kind
    public var defaultValue: TOMLValue?
    public var choices: [String]
    public var note: String?
    public init(key: String, title: String, kind: Kind, defaultValue: TOMLValue? = nil, choices: [String] = [], note: String? = nil) {
        self.key = key; self.title = title; self.kind = kind; self.defaultValue = defaultValue; self.choices = choices; self.note = note
    }

    /// What the plugin sees in `GZYMS_OPT_<KEY>`: a list one item per line, the rest as written.
    public static func envText(_ v: TOMLValue) -> String {
        switch v {
        case .bool(let b): b ? "true" : "false"
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .string(let s): s
        case .ints(let a): a.map(String.init).joined(separator: "\n")
        case .strings(let a): a.joined(separator: "\n")
        }
    }
}

extension TOMLValue: Decodable {
    /// Whatever a TOML value is: a plugin's option default, or the value config.toml holds for it.
    public init(from decoder: Decoder) throws {
        // TOMLDecoder hands arrays out only as unkeyed containers, and a failed element decode still moves its index,
        // so each element type gets a fresh container and the whole array.
        func all<T: Decodable>(_: T.Type) throws -> [T] {
            var a = try decoder.unkeyedContainer()
            var out: [T] = []
            while !a.isAtEnd { out.append(try a.decode(T.self)) }
            return out
        }
        if let s = try? all(String.self) { self = .strings(s); return }
        if let i = try? all(Int.self) { self = .ints(i); return }
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a value Gzyms keeps") }
    }

    /// JSON for `GZYMS_OPTIONS`.
    var json: Any {
        switch self {
        case .bool(let b): b
        case .int(let i): i
        case .double(let d): d
        case .string(let s): s
        case .ints(let a): a
        case .strings(let a): a
        }
    }
}

public func pluginManifest(toml: String, folder: String) -> Result<PluginManifest, NotifyArgsError> {
    struct RawOption: Decodable {
        var key: String?; var title: String?; var type: String?; var `default`: TOMLValue?; var choices: [String]?; var note: String?
    }
    struct Raw: Decodable { var name: String?; var command: String?; var description: String?; var icon: String?; var option: [RawOption]? }
    guard let raw = try? TOMLDecoder().decode(Raw.self, from: Data(toml.utf8)) else {
        return .failure(.init(message: "\(folder)/plugin.toml could not be read"))
    }
    guard let command = raw.command, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
        return .failure(.init(message: "\(folder)/plugin.toml has no command"))
    }
    var options: [PluginOption] = []
    for (n, o) in (raw.option ?? []).enumerated() {
        guard let key = o.key, key.wholeMatch(of: /[a-z][a-z0-9_]*/) != nil else {
            return .failure(.init(message: "\(folder)/plugin.toml: option \(n + 1) needs a key of lowercase letters, digits and _"))
        }
        guard key != "enabled" else { return .failure(.init(message: "\(folder)/plugin.toml: \"enabled\" is Gzyms' own key")) }
        guard let kind = PluginOption.Kind(rawValue: o.type ?? "text") else {
            return .failure(.init(message: "\(folder)/plugin.toml: option \(key) has type \(o.type ?? ""), not toggle, choice, text, number or list"))
        }
        options.append(PluginOption(key: key, title: o.title ?? key, kind: kind, defaultValue: o.default, choices: o.choices ?? [], note: o.note))
    }
    return .success(PluginManifest(folder: folder, name: raw.name ?? folder, command: command,
                                   description: raw.description ?? "", icon: raw.icon, options: options))
}

/// The environment a plugin starts with: each option as `GZYMS_OPT_<KEY>` (the user's value, else the default)
/// and all of them as one JSON object in `GZYMS_OPTIONS`.
public func pluginEnvironment(_ m: PluginManifest, values: [String: TOMLValue]) -> [String: String] {
    var env = ["GZYMS_PLUGIN": m.folder]
    var all: [String: Any] = [:]
    for o in m.options {
        guard let v = values[o.key] ?? o.defaultValue else { continue }
        env["GZYMS_OPT_" + o.key.uppercased()] = PluginOption.envText(v)
        all[o.key] = v.json
    }
    let data = (try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys])) ?? Data("{}".utf8)
    env["GZYMS_OPTIONS"] = String(decoding: data, as: UTF8.self)
    return env
}

/// A pill a plugin puts on the bar.
public struct PluginItem: Equatable, Sendable {
    public var id: String
    public var text: String
    /// An SF Symbol name.
    public var icon: String?
    /// A theme colour name (green, peach, red, …) or a hex.
    public var color: String?
    public var tooltip: String?
    /// Rows of the list a click opens; nil = a click goes straight to the plugin.
    public var menu: [PluginRow]?
    /// The plugin could not get this pill's data: what broke and how to fix it. The pill greys out until a line without it.
    public var error: String?
    /// Seconds in which the plugin promises to say something about this pill again. Silent for much longer = failed.
    /// nil = no promise (a plugin that speaks only when something happens).
    public var expect: Int?
    public init(id: String, text: String, icon: String? = nil, color: String? = nil, tooltip: String? = nil, menu: [PluginRow]? = nil,
                error: String? = nil, expect: Int? = nil) {
        self.id = id; self.text = text; self.icon = icon; self.color = color; self.tooltip = tooltip; self.menu = menu
        self.error = error; self.expect = expect
    }
}

/// Why a pill is greyed out, and since when. The numbers on it are old.
public struct PluginFailure: Equatable, Sendable {
    public var message: String
    public var since: Date
    public init(message: String, since: Date) { self.message = message; self.since = since }
}

/// A pill the host keeps for a plugin: the last line about it, when it came, and since when the plugin has said it failed.
public struct HeldItem: Equatable, Sendable {
    public var item: PluginItem
    public var heard: Date
    public var errorSince: Date?
    public init(item: PluginItem, heard: Date, errorSince: Date? = nil) { self.item = item; self.heard = heard; self.errorSince = errorSince }
}

/// A new line about a pill. An error that carries on keeps the time it started.
public func hold(_ item: PluginItem, previous: HeldItem?, now: Date) -> HeldItem {
    HeldItem(item: item, heard: now, errorSince: item.error == nil ? nil : (previous?.item.error == nil ? now : previous?.errorSince ?? now))
}

/// Failed when the plugin said so, when its process is gone (`exit`), or when it has been silent for much longer
/// than it promised (`expect`: twice that and half a minute, for a slow call). nil = the numbers are fresh.
public func pluginFailure(_ h: HeldItem, exit: PluginFailure?, now: Date) -> PluginFailure? {
    if let exit { return exit }
    if let e = h.item.error { return PluginFailure(message: e, since: h.errorSince ?? h.heard) }
    if let s = h.item.expect, now.timeIntervalSince(h.heard) > Double(s) * 2 + 30 {
        return PluginFailure(message: "No answer for a while. These numbers may be old.", since: h.heard)
    }
    return nil
}

/// One row of a plugin's list: a coloured tag on the left, the text, a detail on the right. A click (left or right)
/// goes back to the plugin with the row's id; a row without an id is a label, `separator` a line.
public struct PluginRow: Equatable, Sendable {
    public var id: String?
    public var text: String
    public var tag: String?
    public var color: String?
    public var detail: String?
    public var separator: Bool
    /// Drawn faded: an idle agent, or one from a source that failed. Gzyms' own rows only, not in the protocol.
    public var dim: Bool
    public init(id: String? = nil, text: String = "", tag: String? = nil, color: String? = nil, detail: String? = nil, separator: Bool = false,
                dim: Bool = false) {
        self.id = id; self.text = text; self.tag = tag; self.color = color; self.detail = detail; self.separator = separator; self.dim = dim
    }
}

/// A pill on the bar with the plugin it belongs to (clicks go back to that plugin).
public struct PluginPill: Equatable, Sendable {
    public var plugin: String
    public var item: PluginItem
    /// nil = fresh. Set = greyed out with a warning, and its popup says why.
    public var failure: PluginFailure?
    public init(plugin: String, item: PluginItem, failure: PluginFailure? = nil) { self.plugin = plugin; self.item = item; self.failure = failure }
    /// Two plugins may both call a pill "status".
    public var key: String { "\(plugin)/\(item.id)" }
}

/// A plugin folder as Settings lists it.
public struct PluginStatus: Equatable, Sendable {
    public var folder: String, name: String, description: String
    public var enabled: Bool, running: Bool
    /// Why it does not run (a broken manifest, it keeps dying); nil = fine.
    public var problem: String?
    /// The form Settings draws for it.
    public var options: [PluginOption]
    /// The user edited this catalog plugin and the catalog has another version: Settings offers to replace it.
    public var catalogNewer: Bool
    /// An SF Symbol name from the manifest.
    public var icon: String?
    public init(folder: String, name: String, description: String, enabled: Bool, running: Bool, problem: String? = nil,
                options: [PluginOption] = [], catalogNewer: Bool = false, icon: String? = nil) {
        self.folder = folder; self.name = name; self.description = description; self.enabled = enabled; self.running = running
        self.problem = problem; self.options = options; self.catalogNewer = catalogNewer; self.icon = icon
    }
}

/// One line a plugin wrote on stdout.
public enum PluginMessage: Equatable, Sendable {
    case item(PluginItem)
    case removeItem(String)
    case notify(GzymsNotification)
    /// Takes one of its notifications off the bar and out of the list (the full id, as `notify` made it).
    case dismiss(String)
    /// A line for Gzyms's log, e.g. what a click did.
    case log(String)
}

/// nil = not a message (a half line, garbage, a field missing); the host logs it.
public func pluginMessage(_ line: String, plugin: String, now: Date) -> PluginMessage? {
    struct Row: Decodable { var id, text, tag, color, detail: String?; var separator: Bool? }
    struct Item: Decodable {
        var id: String?; var text: String?; var icon: String?; var color: String?; var tooltip: String?; var remove: Bool?; var menu: [Row]?
        var error: String?; var expect: Int?
    }
    struct Notify: Decodable {
        var id: String?, title: String?, subtitle: String?, body: String?, level: String?, sound: String?, link: String?
        var alt_link: String?, alt_label: String?, row: String?
    }
    struct Raw: Decodable { var item: Item?; var notify: Notify?; var dismiss: String?; var log: String? }
    guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)) else { return nil }
    if let i = raw.item, let id = i.id, !id.isEmpty {
        if i.remove == true { return .removeItem(id) }
        guard let text = i.text else { return nil }
        let menu = i.menu.map { rows in
            rows.map { PluginRow(id: $0.id, text: $0.text ?? "", tag: $0.tag, color: $0.color, detail: $0.detail, separator: $0.separator ?? false) }
        }
        return .item(PluginItem(id: id, text: text, icon: i.icon, color: i.color, tooltip: i.tooltip, menu: menu,
                                error: i.error.flatMap { $0.isEmpty ? nil : $0 }, expect: i.expect.flatMap { $0 > 0 ? $0 : nil }))
    }
    if let n = raw.notify, let title = n.title, !title.isEmpty {
        let level = n.level.flatMap(NotifyLevel.init(rawValue:)) ?? .info
        // A plugin's own id updates its earlier notification. Namespaced with ":", which a folder name cannot hold,
        // so plugin "log" can never pass for "log-watcher".
        let id = "plugin:\(plugin):" + (n.id ?? UUID().uuidString)
        var note = GzymsNotification(id: id, app: nil, level: level, title: title, subtitle: n.subtitle, body: n.body,
                                     link: n.link, altLink: n.alt_link, sound: n.sound, at: now)
        note.altLabel = n.alt_label
        note.row = n.row
        return .notify(note)
    }
    if let d = raw.dismiss, !d.isEmpty { return .dismiss("plugin:\(plugin):" + d) }
    if let l = raw.log, !l.isEmpty { return .log(l) }
    return nil
}

/// What Gzyms writes on a plugin's stdin: `click` / `right_click` on a pill or a row, `open` when its list opens,
/// `notify_open` when someone opens one of its notifications that has no link (the id is the plugin's own),
/// `notify_alt` for the second action of one with `alt_label` and no `alt_link`.
public enum PluginEvent: String, CaseIterable, Sendable {
    case click, rightClick = "right_click", open, notifyOpen = "notify_open", notifyAlt = "notify_alt"
}

/// A plugin's text in pieces: `:name:` with an SF Symbol name inside is that symbol, the rest stays text.
/// `:name@red:` draws it in that colour (a theme colour name or `#rrggbb`), the text's colour otherwise.
/// A name that is no symbol (`12:30:00`, `:nope:`) stays text as written.
public enum TextPiece: Equatable, Sendable { case text(String), symbol(String, color: String? = nil) }

public func textPieces(_ s: String, isSymbol: (String) -> Bool) -> [TextPiece] {
    var out: [TextPiece] = [], rest = s[...]
    func add(_ t: Substring) {
        guard !t.isEmpty else { return }
        if case .text(let prev)? = out.last { out[out.count - 1] = .text(prev + t) } else { out.append(.text(String(t))) }
    }
    while let m = rest.firstMatch(of: /:([a-z][a-z0-9]*(?:\.[a-z0-9]+)*)(?:@([a-z][a-z0-9_]*|#[0-9a-fA-F]{6}))?:/) {
        if isSymbol(String(m.1)) {
            add(rest[..<m.range.lowerBound])
            out.append(.symbol(String(m.1), color: m.2.map(String.init)))
            rest = rest[m.range.upperBound...]
        } else {  // keep this colon as text, look again from the next one
            let next = rest.index(after: m.range.lowerBound)
            add(rest[..<next])
            rest = rest[next...]
        }
    }
    add(rest)
    return out
}

/// The plugin behind a notification id and the id it gave it. Only plugins post such ids: Gzyms drops them from outside.
public func pluginNoteOwner(_ noteID: String, plugins: [String]) -> (plugin: String, id: String)? {
    let parts = noteID.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "plugin", plugins.contains(String(parts[1])) else { return nil }
    return (String(parts[1]), String(parts[2]))
}

public func pluginEventLine(_ e: PluginEvent, id: String) -> String {
    let data = (try? JSONEncoder().encode(["event": e.rawValue, "id": id])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

/// `gzyms plugin new <folder>`: a working click counter in bash that shows the whole protocol.
public func pluginScaffold(folder: String) -> (manifest: String, script: String) {
    let manifest = """
    # A Gzyms plugin. The whole protocol: gzyms skill plugins
    name = "\(folder)"
    description = "Counts clicks on its pill. Edit plugin.sh to make it yours."
    command = "./plugin.sh"
    icon = "puzzlepiece.extension"

    # Settings → Plugins draws a form from these; the plugin reads GZYMS_OPT_<KEY> (all of them: GZYMS_OPTIONS, JSON).
    # type = toggle | choice (with choices = [...]) | text | number | list. A change restarts the plugin.
    [[option]]
    key = "label"
    title = "Pill label"
    type = "text"
    default = "clicked"
    note = "the word before the count"

    """
    let script = #"""
    #!/bin/bash
    # Gzyms plugin protocol, one JSON object per line (all of it, menus included: gzyms skill plugins):
    #   you -> Gzyms (stdout): {"item":{"id":"x","text":"…","icon":"<SF Symbol>","color":"green"}}
    #                          {"item":{"id":"x","remove":true}}
    #                          {"notify":{"title":"…","body":"…","level":"info|warning|error|critical","sound":"success"}}
    #   Gzyms -> you (stdin):  {"event":"click","id":"x"}
    # When stdin ends, Gzyms is gone: exit. Print only on change, Gzyms redraws on every line.
    # Gzyms starts this once: after editing it, turn the plugin off and on (Settings → Plugins) to run the new code.
    n=0
    label="${GZYMS_OPT_LABEL:-clicked}"  # the "Pill label" option from plugin.toml
    pill() { echo "{\"item\":{\"id\":\"counter\",\"text\":\"$label $n\",\"icon\":\"hand.tap\",\"color\":\"green\"}}"; }
    pill
    while read -r line; do
      case "$line" in
        *'"click"'*)
          n=$((n + 1)); pill
          if [ $((n % 5)) -eq 0 ]; then echo "{\"notify\":{\"title\":\"$n clicks\",\"body\":\"from the example plugin\",\"sound\":\"success\"}}"; fi
          ;;
      esac
    done

    """#
    return (manifest, script)
}
