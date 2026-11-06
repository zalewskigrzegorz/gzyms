import Foundation

/// One `gzyms` command: help, completions and the typo check all read this table.
public struct CLICommand: Sendable {
    public let name: String
    /// What follows the name in `gzyms help`.
    public let usage: String
    public let summary: String
    /// What completes after the name: subcommands, values and flags.
    public let words: [String]
    /// For testing Gzyms itself: runs, but not listed in help.
    public var debug = false
}

public let cliTable: [CLICommand] = [
    .init(name: "notify", usage: "--title <text> [flags]", summary: "Show a notification on the island.", words: notifyFlags + notifySwitches),
    .init(name: "set", usage: "<key> <value>", summary: "Change a setting in config.toml. Phone push keys go to the Keychain.", words: []),
    .init(name: "unset", usage: "<key>", summary: "Put a setting back to its default.", words: []),
    .init(name: "theme", usage: "[name | -l, --list]", summary: "Print, list or switch the theme.", words: ["--list"] + Theme.all.map(\.name)),
    .init(name: "settings", usage: "[tab]", summary: "Open the settings panel, on a tab when given.", words: []),
    .init(name: "keys", usage: "on|off", summary: "Turn the keyboard mode on or off.", words: ["on", "off"]),
    .init(name: "dnd", usage: "on [minutes]|off", summary: "Turn Do Not Disturb on or off.", words: ["on", "off"]),
    .init(name: "notifications", usage: "[--json] | dismiss <id> | clear", summary: "List the notifications Gzyms holds, dismiss one or clear the lists.",
          words: ["--json", "dismiss", "clear"]),
    .init(name: "debug", usage: "[notifications|keys|cpu] [--json]", summary: "Ask the running Gzyms what it sees: notification setup, keys, what costs CPU.",
          words: ["--json"] + debugTopics),
    .init(name: "hud", usage: "", summary: "Open the usage HUD, a second call closes it.", words: []),
    .init(name: "report", usage: "", summary: "Put a zip for a bug report on the Desktop.", words: []),
    .init(name: "agents", usage: "status | install claude | remove claude", summary: "Agents on the bar: their state, the Claude Code plugin in or out.",
          words: ["status", "install", "remove", "claude"]),
    .init(name: "plugin", usage: "list|new <name>|add <name>|remove <name>", summary: "Manage plugins.", words: ["list", "new", "add", "remove"]),
    .init(name: "skill", usage: "[topic] | install [-a, --agents] [-y, --yes]", summary: "The guide for coding agents.",
          words: ["install", "--agents", "--yes"] + skillTopics),
    .init(name: "help", usage: "[command]", summary: "This list, or one command's flags.", words: []),
    .init(name: "completions", usage: "nu|zsh|fish|bash | install [shell] [-y, --yes]", summary: "Tab completion: print the script, or install it.",
          words: ["install", "--yes"] + completionShells),
    .init(name: "meeting-test", usage: "[minutes]", summary: "A pretend meeting reminder.", words: [], debug: true),
    .init(name: "message", usage: "whats-new|untested-macos", summary: "Show a message from Gzyms now.", words: ["whats-new", "untested-macos"], debug: true),
]

/// Every first word `gzyms` takes. Anything else is refused: a typo once started a second bar (Greg, 2026-11-01).
public let cliCommands = cliTable.map(\.name)
public let completionShells = ["nu", "zsh", "fish", "bash"]

/// The one-letter form of each flag, per command ("" = before any command). Greg: wherever a letter is free.
public let cliShortFlags: [String: [String: String]] = [
    "": ["-v": "--version"],
    "notify": notifyShort,
    "theme": ["-l": "--list"],
    "skill": ["-a": "--agents", "-y": "--yes"],
    "completions": ["-y": "--yes"],
]

/// The arguments with every short flag written out, so each command parses only the long ones. notify keeps its own:
/// a value there may look like a flag (`--body -t`).
public func expandShortFlags(_ args: [String]) -> [String] {
    guard let first = args.first else { return args }
    if let long = cliShortFlags[""]?[first] { return [long] + args.dropFirst() }
    guard first != "notify", let map = cliShortFlags[first] else { return args }
    return [first] + args.dropFirst().map { map[$0] ?? $0 }
}
let helpWords = ["--help", "-h"]

/// nil = run it (no word starts the bar). Otherwise the text for stderr: the problem, the closest commands, the list.
public func cliProblem(_ args: [String]) -> String? {
    guard let first = args.first, first != "--version", first != "-v", !helpWords.contains(first), !cliCommands.contains(first) else { return nil }
    let visible = cliTable.filter { !$0.debug }.map(\.name)
    let distances = visible.map { ($0, editDistance(first, $0)) }
    let best = distances.map(\.1).min() ?? 0
    let close = best <= 2 ? distances.filter { $0.1 == best }.map(\.0) : []
    return "gzyms: unknown command \"\(first)\"\n"
        + (close.isEmpty ? "" : "did you mean: \(close.joined(separator: ", "))\n")
        + "gzyms help lists the commands.\n"
}

/// The command a help request is about: `help`, `help notify`, `notify --help`. nil = not a help request.
/// "" = the whole list.
public func helpTopic(_ args: [String]) -> String? {
    guard let first = args.first else { return nil }
    if first == "help" || helpWords.contains(first) { return args.dropFirst().first ?? "" }
    if args.count > 1, helpWords.contains(args[1]) { return first }
    return nil
}

/// `gzyms help` and `gzyms help <command>`. nil = no such command.
public func helpText(_ topic: String, guide: String = skillText(topic: "guide") ?? "") -> String? {
    if topic.isEmpty {
        let shown = cliTable.filter { !$0.debug }
        let width = (shown.map(\.name.count).max() ?? 0) + 2
        return "gzyms: the status bar. Run with no command, it starts the bar.\n\n"
            + shown.map { "  " + $0.name.padding(toLength: width, withPad: " ", startingAt: 0) + $0.summary }.joined(separator: "\n")
            + "\n  -v, --version" + String(repeating: " ", count: max(1, width - 13)) + "Print the version.\n\n"
            + "gzyms help <command> shows its flags.\n"
            + "Tab completion: gzyms help completions.\n"
            + "For coding agents: gzyms skill.\n"
    }
    guard let c = cliTable.first(where: { $0.name == topic }) else { return nil }
    var out = "gzyms \(c.name) \(c.usage)".trimmingCharacters(in: .whitespaces) + "\n\(c.summary)\n"
    switch c.name {
    // The flags with what they do, from the guide's table: the drift test keeps that table whole.
    case "notify": out += "\n" + guide.split(separator: "\n").filter { $0.hasPrefix("| `--") }.map(flagRow).joined(separator: "\n") + "\n"
    case "completions":
        out += """

            gzyms completions install           for every shell on this Mac
            gzyms completions install nu        or only the one named: nu, zsh, fish, bash
            It shows what it writes and asks first. --yes skips the question.
            nu and fish get a file: run it again after updating Gzyms. zsh and bash get one line in their rc file.
            Open a new shell afterwards.

            """
    default: break
    }
    return out
}

/// "| `--title <text>` | Required. |" → "  --title <text>   Required."
private func flagRow(_ line: Substring) -> String {
    let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`", with: "") }
    guard cells.count >= 2 else { return String(line) }
    let long = String(cells[0].split(separator: " ").first ?? "")
    let short = cliShortFlags["notify"]?.first { $0.value == long }.map { "\($0.key), " } ?? "    "
    return "  " + (short + cells[0]).padding(toLength: max(short.count + cells[0].count, 30), withPad: " ", startingAt: 0) + " " + cells[1]
}

/// Each notify flag's first sentence, from the guide's table (the one the drift test keeps whole).
func notifyFlagDocs(_ guide: String) -> [String: String] {
    var out: [String: String] = [:]
    for line in guide.split(separator: "\n") where line.hasPrefix("| `--") {
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`", with: "") }
        guard cells.count >= 2, let flag = cells[0].split(separator: " ").first else { continue }
        out[String(flag)] = cells[1].components(separatedBy: ". ").first.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
    }
    return out
}

/// A completion script for `shell`, nil for one Gzyms does not know. `extra` adds words the app knows (settings tabs).
public func completionScript(_ shell: String, extra: [String: [String]] = [:], guide: String = skillText(topic: "guide") ?? "") -> String? {
    let shown = cliTable.filter { !$0.debug }
    let words = Dictionary(uniqueKeysWithValues: shown.map { ($0.name, $0.words + (extra[$0.name] ?? [])) })
        .merging(["help": shown.map(\.name)]) { _, b in b }
    let names = shown.map(\.name)
    // Double quotes keep an apostrophe ("one command's flags"). shortcut: no $ in any word or summary, add an escape if one comes.
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    switch shell {
    case "nu":
        // An extern per command: nu completes the flags itself and shows each one's comment. The completers return
        // records, so the command list shows what each command does.
        let docs = notifyFlagDocs(guide)
        func rec(_ value: String, _ doc: String) -> String { "{value: \(q(value)), description: \(q(doc))}" }
        var s = "# gzyms completions for nushell (gzyms help completions)\n"
        s += "def \"nu-complete gzyms\" [] { [\(shown.map { rec($0.name, $0.summary) }.joined(separator: " "))] }\n"
        s += "# Gzyms, the status bar\nextern \"gzyms\" [\n  command?: string@\"nu-complete gzyms\"\n  --version(-v)  # Print the version\n]\n"
        for c in shown {
            let flags = (words[c.name] ?? []).filter { $0.hasPrefix("--") }
            let values = (words[c.name] ?? []).filter { !$0.hasPrefix("--") }
            var params: [String] = []
            if !values.isEmpty {
                let summaries = Dictionary(uniqueKeysWithValues: shown.map { ($0.name, $0.summary) })
                let items = values.map { c.name == "help" ? rec($0, summaries[$0] ?? "") : q($0) }
                s += "def \"nu-complete gzyms \(c.name)\" [] { [\(items.joined(separator: " "))] }\n"
                params.append("arg?: string@\"nu-complete gzyms \(c.name)\"")
            }
            params.append("...rest: string")
            for f in flags {
                let doc = docs[f].map { "  # " + $0 } ?? ""
                if c.name == "notify", f == "--level" {
                    params.append("--level(-l): string@\"nu-complete gzyms level\"" + doc)
                } else {
                    let short = cliShortFlags[c.name]?.first { $0.value == f }.map { "(\($0.key))" } ?? ""
                    params.append((notifyFlags.contains(f) ? "\(f)\(short): string" : f + short) + doc)
                }
            }
            if c.name == "notify" {
                s += "def \"nu-complete gzyms level\" [] { [\(NotifyLevel.allCases.map(\.rawValue).map(q).joined(separator: " "))] }\n"
            }
            s += "# \(c.summary)\nextern \"gzyms \(c.name)\" [\n" + params.map { "  " + $0 }.joined(separator: "\n") + "\n]\n"
        }
        return s
    case "zsh":
        var s = "#compdef gzyms\n# gzyms completions for zsh (gzyms help completions)\n_gzyms() {\n"
        s += "  if (( CURRENT == 2 )); then compadd -- \(names.joined(separator: " ")) --version; return; fi\n  case $words[2] in\n"
        for (n, w) in words.sorted(by: { $0.key < $1.key }) where !w.isEmpty { s += "    \(n)) compadd -- \(w.joined(separator: " ")) ;;\n" }
        return s + "  esac\n}\ncompdef _gzyms gzyms\n"
    case "bash":
        var s = "# gzyms completions for bash (gzyms help completions)\n_gzyms() {\n  local cur=${COMP_WORDS[COMP_CWORD]} w\n"
        s += "  if (( COMP_CWORD == 1 )); then w=\"\(names.joined(separator: " ")) --version\"\n  else case ${COMP_WORDS[1]} in\n"
        for (n, w) in words.sorted(by: { $0.key < $1.key }) where !w.isEmpty { s += "    \(n)) w=\"\(w.joined(separator: " "))\" ;;\n" }
        return s + "  esac; fi\n  COMPREPLY=($(compgen -W \"$w\" -- \"$cur\"))\n}\ncomplete -F _gzyms gzyms\n"
    case "fish":
        var s = "# gzyms completions for fish (gzyms help completions)\ncomplete -c gzyms -f\n"
        for c in shown { s += "complete -c gzyms -n __fish_use_subcommand -a \(c.name) -d \(q(c.summary))\n" }
        for (n, w) in words.sorted(by: { $0.key < $1.key }) where !w.isEmpty {
            s += "complete -c gzyms -n '__fish_seen_subcommand_from \(n)' -a \(q(w.joined(separator: " ")))\n"
        }
        return s
    default: return nil
    }
}

/// Where `gzyms completions install` puts it: a file with the script, or a line added to an rc file.
public enum CompletionInstall: Equatable, Sendable {
    case file(URL)
    case rcLine(URL, String)
}

/// `nuAutoload` is what nu says `$nu.user-autoload-dirs | first` is; nil = the usual ~/.config/nushell/autoload.
public func completionInstallTarget(shell: String, home: URL, nuAutoload: URL? = nil) -> CompletionInstall? {
    switch shell {
    case "nu": .file((nuAutoload ?? home.appendingPathComponent(".config/nushell/autoload")).appendingPathComponent("gzyms.nu"))
    case "fish": .file(home.appendingPathComponent(".config/fish/completions/gzyms.fish"))
    // compdef exists only after compinit: without it the line does nothing instead of failing every shell.
    case "zsh": .rcLine(home.appendingPathComponent(".zshrc"), "(( $+functions[compdef] )) && source <(gzyms completions zsh)")
    case "bash": .rcLine(home.appendingPathComponent(".bashrc"), "source <(gzyms completions bash)")
    default: nil
    }
}

/// The rc file with the line added once; nil when it is already there.
public func addingRCLine(_ line: String, to text: String) -> String? {
    if text.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == line }) { return nil }
    return text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + "\n# gzyms tab completion\n\(line)\n"
}

/// Levenshtein, on characters.
func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var row = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
        var prev = row[0]
        row[0] = i
        for j in 1...max(b.count, 1) where !b.isEmpty {
            let keep = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
            prev = keep
        }
    }
    return row[b.count]
}
