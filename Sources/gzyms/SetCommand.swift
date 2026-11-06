import AppKit
import GzymsCore

/// `gzyms set <key> <value>` and `gzyms unset <key>`: any setting in config.toml, by its dotted name as in the file.
/// The running bar and HUD pick it up at once, as with a change in Settings.
enum SetCommand {
    static func run(_ args: [String], remove: Bool) -> Never {
        let verb = remove ? "unset" : "set"
        guard let dotted = args.first, let (table, key) = configKey(dotted), remove ? args.count == 1 : args.count == 2 else {
            fail(verb, """
            usage: gzyms set <key> <value> · gzyms unset <key> (back to the default)
              gzyms set appearance.animations false
              gzyms set appearance.banner_entry pop    (icon, drop, notch, unroll, pop, fade)
              gzyms set widgets.cpu false
              gzyms set agents.done_after 0
              gzyms set notifications.apps."com.mitchellh.ghostty".banner false
              gzyms set calendar.points [5, 0]
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
        let me = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").filter { $0.processIdentifier != me }
            .forEach { kill($0.processIdentifier, SIGHUP) }
        print(remove ? "\(dotted): back to the default" : "\(dotted) = \(args[1])")
        exit(0)
    }

    private static func fail(_ verb: String, _ message: String) -> Never {
        FileHandle.standardError.write(Data("gzyms \(verb): \(message)\n".utf8))
        exit(1)
    }
}
