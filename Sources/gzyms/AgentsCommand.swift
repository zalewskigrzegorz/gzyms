import Foundation
import GzymsCore

/// `gzyms agents status | install claude | remove claude`. The plugin goes in and out through Claude Code's own CLI.
enum AgentsCommand {
    static func run(_ args: [String]) -> Never {
        switch (args.first, args.dropFirst().first) {
        case (nil, _), ("status"?, nil): status()
        case ("install"?, "claude"?): change(.install)
        case ("remove"?, "claude"?): change(.remove)
        default: fail("usage: gzyms agents status | install claude | remove claude")
        }
    }

    private static func run(_ path: String, _ args: [String]) -> CommandOutput { AgentsHost.runSync(path, args, timeout: 120) }
    private static var claude: String? { claudeBinary(home: NSHomeDirectory(), run: run, executable: FileManager.default.isExecutableFile) }

    private static func status() -> Never {
        let config = loadConfig(toml: try? String(contentsOf: ThemeCommand.configFile, encoding: .utf8)).config
        print("tuios: \(config.agentsTuios ? "on" : "off")")
        print("Claude Code: \(config.agentsClaude ? "on" : "off")")
        switch claudePluginState(claude: claude, run: run) {
        case .success(.noClaude): print("Claude Code plugin: \(claudeMissing)")
        case .success(let s): print("Claude Code plugin: \(s.line)")
        case .failure(let e): fail("Claude Code plugin: could not check. \(e.message)")
        }
        exit(0)
    }

    private static func change(_ action: ClaudePluginAction) -> Never {
        let claude = claude
        if let e = changeClaudePlugin(action, claude: claude, run: run, say: { print($0) }) { fail("gzyms agents: \(e.message)") }
        let line = (try? claudePluginState(claude: claude, run: run).get())?.line ?? "Done"
        print(action == .install ? "\(line). \(claudePluginReloadNote)" : line)
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
