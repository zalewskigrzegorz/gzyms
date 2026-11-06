import AppKit
import GzymsCore

/// `gzyms set <key> <value>` and `gzyms unset <key>`: any setting in config.toml, by its dotted name as in the file.
/// The phone push keys (`PhoneSecret`) go to the Keychain instead. The running bar and HUD pick it up at once, as
/// with a change in Settings.
enum SetCommand {
    static func run(_ args: [String], remove: Bool) -> Never {
        let verb = remove ? "unset" : "set"
        if let dotted = args.first, let secret = PhoneSecret(account: dotted) { runSecret(secret, args, remove: remove, verb: verb) }
        guard let dotted = args.first, let (table, key) = configKey(dotted), remove ? args.count == 1 : args.count == 2 else {
            fail(verb, """
            usage: gzyms set <key> <value> · gzyms unset <key> (back to the default)
              gzyms set appearance.animations false
              gzyms set appearance.banner_entry pop    (icon, drop, notch, unroll, pop, fade)
              gzyms set widgets.cpu false
              gzyms set agents.done_after 0
              gzyms set notifications.apps."com.mitchellh.ghostty".banner false
              gzyms set calendar.points [5, 0]
            phone push keys go to the Keychain, not the file. Leave the value out to keep it off history and ps:
              pbpaste | gzyms set notifications.phone.pushover_token
              gzyms set notifications.phone.url    (asks, hidden)
              (also pushover_user. An inline value or - works too.)
            the file: \(ThemeCommand.configFile.path)
            """)
        }
        let file = ThemeCommand.configFile
        let before = try? String(contentsOf: file, encoding: .utf8)
        let after = setting(key, to: remove ? nil : tomlValue(cli: args[1]), in: .table(table), toml: before)
        // Unchanged text: the same value is there already, or the key spans several lines (then removing it changes nothing either).
        if after == before, !remove, setting(key, to: nil, in: .table(table), toml: before) == before {
            fail(verb, "\(dotted) holds a value over several lines. Change it in the file.")
        }
        // A typo in the key or a wrong value shows up as a new problem in the config check: then nothing is written.
        let old = Set(loadConfig(toml: before).problems)
        let new = loadConfig(toml: after).problems.filter { !old.contains($0) }
        if !new.isEmpty { fail(verb, new.joined(separator: "\n") + "\nnothing written") }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try after.write(to: file, atomically: true, encoding: .utf8)
        } catch { fail(verb, "could not write \(file.path): \(error)") }
        reloadRunning()
        print(remove ? "\(dotted): back to the default" : "\(dotted) = \(args[1])")
        exit(0)
    }

    /// A phone push key: the Keychain only, config.toml untouched, the value never printed.
    private static func runSecret(_ s: PhoneSecret, _ args: [String], remove: Bool, verb: String) -> Never {
        let value: String?
        switch secretInput(args, remove: remove) {
        case .remove?: value = nil
        case .inline(let v)?: value = v
        case .stdin?: value = readSecret()
        case nil:
            fail(verb, """
            usage: pbpaste | gzyms set \(s.account)
                   gzyms set \(s.account)    (asks, hidden)
                   gzyms unset \(s.account)
            """)
        }
        // Blank would delete it: an Enter by mistake must not.
        if !remove, value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { fail(verb, "no value, nothing saved") }
        if let problem = savePhoneSecret(s, value, store: KeychainStore()) { fail(verb, problem + "\nnothing saved") }
        reloadRunning()
        print(remove ? "\(s.account): removed from the Keychain" : "\(s.account): saved in the Keychain")
        exit(0)
    }

    /// One line from stdin. On a terminal: a prompt with echo off, put back after Enter or Ctrl-C.
    private static func readSecret() -> String? {
        guard isatty(STDIN_FILENO) != 0 else { return readLine(strippingNewline: true) }
        var t = termios()
        tcgetattr(STDIN_FILENO, &t)
        savedTerminal = t
        t.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
        signal(SIGINT) { _ in restoreTerminal(); _exit(130) }
        FileHandle.standardError.write(Data("Value (hidden): ".utf8))
        let line = readLine(strippingNewline: true)
        restoreTerminal()
        FileHandle.standardError.write(Data("\n".utf8))
        return line
    }

    /// SIGHUP makes the running bar read config.toml and the Keychain again.
    private static func reloadRunning() {
        let me = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").filter { $0.processIdentifier != me }
            .forEach { kill($0.processIdentifier, SIGHUP) }
    }

    private static func fail(_ verb: String, _ message: String) -> Never {
        FileHandle.standardError.write(Data("gzyms \(verb): \(message)\n".utf8))
        exit(1)
    }
}

/// The terminal as it was before the hidden prompt. Global: the SIGINT handler cannot capture.
nonisolated(unsafe) private var savedTerminal: termios?

private func restoreTerminal() {
    guard var t = savedTerminal else { return }
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
}
