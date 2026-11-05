import Foundation
import GzymsCore

/// `gzyms plugin list | new <folder> | remove <folder>`. The running bar watches the plugins folder and follows.
enum PluginCommand {
    static var dir: URL { Paths.configDir(env: ProcessInfo.processInfo.environment).appendingPathComponent("plugins") }

    static func run(_ args: [String]) -> Never {
        switch args.first {
        case "list"?, nil: list()
        case "new"?: new(args.dropFirst().first)
        case "add"?: add(args.dropFirst().first)
        case "remove"?: remove(args.dropFirst().first)
        default: fail("gzyms plugin: no command \"\(args[0])\" (list, new <name>, add <name>, remove <name>)")
        }
    }

    /// A ready plugin from the catalog, under its own name.
    private static func add(_ name: String?) -> Never {
        guard let name, let c = pluginCatalog.first(where: { $0.name == name }) else {
            print("gzyms plugin add <name>, one of:")
            pluginCatalog.forEach { print("  \($0.name)\t\($0.summary)") }
            exit(name == nil ? 0 : 1)
        }
        do { try installCatalogPlugin(in: dir, c) }
        catch { fail("gzyms plugin: \((error as? NotifyArgsError)?.message ?? error.localizedDescription)") }
        print("made \(dir.appendingPathComponent(name).path)\nset it up in Settings → Plugins → \(name).")
        exit(0)
    }

    private static func write(folder name: String, manifest: String, script: String) {
        do { try installPlugin(in: dir, folder: name, manifest: manifest, script: script) }
        catch { fail("gzyms plugin: \((error as? NotifyArgsError)?.message ?? error.localizedDescription)") }
    }

    private static func list() -> Never {
        let disabled = loadConfig(toml: try? String(contentsOf: ThemeCommand.configFile, encoding: .utf8)).config.disabledPlugins
        let folders = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        var shown = 0
        for f in folders where !isPluginBackup(f) {
            guard let toml = try? String(contentsOf: dir.appendingPathComponent(f).appendingPathComponent("plugin.toml"), encoding: .utf8) else { continue }
            shown += 1
            switch pluginManifest(toml: toml, folder: f) {
            case .success(let m): print("\(f)\t\(disabled.contains(f) ? "off" : "on")\t\(m.name)")
            case .failure(let e): print("\(f)\tbroken\t\(e.message)")
            }
        }
        if shown == 0 { print("no plugins in \(dir.path) (make one: gzyms plugin new <name>)") }
        exit(0)
    }

    private static func new(_ name: String?) -> Never {
        guard let name, name.wholeMatch(of: /[a-z0-9][a-z0-9_-]*/) != nil else {
            fail("gzyms plugin new <name>: lowercase letters, digits, - and _ (it becomes the folder and the config key)")
        }
        let s = pluginScaffold(folder: name)
        write(folder: name, manifest: s.manifest, script: s.script)
        print("""
        made \(dir.appendingPathComponent(name).path)
        the bar shows its pill in a moment; click it. Edit plugin.sh to make it yours.
        after an edit, turn it off and on in Settings → Plugins: Gzyms keeps running the version it started.
        """)
        exit(0)
    }

    private static func remove(_ name: String?) -> Never {
        guard let name, !name.contains("/"), !name.isEmpty else { fail("gzyms plugin remove <name>") }
        let folder = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: folder.path) else { fail("gzyms plugin remove: no plugin \"\(name)\"") }
        do { try FileManager.default.trashItem(at: folder, resultingItemURL: nil) } catch { fail("gzyms plugin remove: \(error.localizedDescription)") }
        print("moved \(name) to the Trash")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
