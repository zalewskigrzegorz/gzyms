import AppKit
import GzymsCore

/// `gzyms theme [name | --list]`: print the theme, list them all, or save a new one and tell the running bar and HUD to reload.
enum ThemeCommand {
    static var configFile: URL {
        Paths.configDir(env: ProcessInfo.processInfo.environment).appendingPathComponent("config.toml")
    }

    static func run(_ name: String?) -> Never {
        let current = try? String(contentsOf: configFile, encoding: .utf8)
        if name == "--list" {
            Theme.all.forEach { print($0.name) }
            exit(0)
        }
        // For Probe's Themes tab: every theme with its colours, and which one is on.
        if name == "--json" {
            let rows = Theme.all.map { t in
                ["name": t.name, "base": t.base, "surface": t.surface, "text": t.text, "red": t.red, "peach": t.peach,
                 "gold": t.gold, "green": t.green, "sky": t.sky, "mauve": t.mauve]
            }
            let out: [String: Any] = ["current": loadConfig(toml: current).config.theme.name, "themes": rows]
            print(String(decoding: (try? JSONSerialization.data(withJSONObject: out)) ?? Data(), as: UTF8.self))
            exit(0)
        }
        guard let name else {
            print("theme: \(loadConfig(toml: current).config.theme.name) (\(Theme.all.count) themes, gzyms theme --list)")
            exit(0)
        }
        guard Theme.named(name) != nil else {
            let near = Theme.all.map(\.name).filter { $0.contains(name.lowercased()) }.prefix(8)
            FileHandle.standardError.write(Data("gzyms theme: no theme \"\(name)\"\(near.isEmpty ? "" : ", close: \(near.joined(separator: ", "))") (gzyms theme --list)\n".utf8))
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try settingTheme(name, in: current).write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("gzyms theme: could not write \(configFile.path): \(error)\n".utf8))
            exit(1)
        }
        // Bar and HUD share the bundle id; both reload their config on SIGHUP.
        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.gzyms").filter { $0.processIdentifier != me }
        running.forEach { kill($0.processIdentifier, SIGHUP) }
        print("theme: \(name)" + (running.isEmpty ? " (Gzyms is not running, applies on next start)" : ""))
        exit(0)
    }
}
