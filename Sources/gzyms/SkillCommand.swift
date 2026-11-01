import Foundation
import GzymsCore

/// `gzyms skill [topic]` prints the guide for coding agents, `gzyms skill install [--yes] [--agents]` puts a stub SKILL.md
/// in the agents' skill folders. Nothing is written without a yes.
enum SkillCommand {
    static func run(_ args: [String]) -> Never {
        if args.first == "install" { install(Array(args.dropFirst())) }
        let topic = args.first ?? "guide"
        guard let text = skillText(topic: topic) else {
            fail("gzyms skill: no topic \"\(topic)\" (topics: \(skillTopics.joined(separator: ", ")), or install)")
        }
        print("gzyms \(gzymsVersion)\n")
        print(text, terminator: "")
        exit(0)
    }

    private static func install(_ flags: [String]) -> Never {
        if let bad = flags.first(where: { $0 != "--yes" && $0 != "--agents" }) {
            fail("gzyms skill install: no flag \(bad) (--yes, --agents)")
        }
        let env = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory())
        let fm = FileManager.default
        let targets = skillInstallTargets(home: home, agentsExists: fm.fileExists(atPath: home.appendingPathComponent(".agents").path),
                                          forceAgents: flags.contains("--agents"))
        print("gzyms skill install writes:")
        targets.forEach { print("  \($0.path)") }
        if !flags.contains("--yes") {
            print("write these? [y/N] ", terminator: "")
            guard readLine()?.lowercased().hasPrefix("y") == true else { print("nothing written"); exit(1) }
        }
        for t in targets {
            do {
                try fm.createDirectory(at: t.deletingLastPathComponent(), withIntermediateDirectories: true)
                try skillStub.write(to: t, atomically: true, encoding: .utf8)
            } catch { fail("gzyms skill install: could not write \(t.path): \(error.localizedDescription)") }
        }
        print("done. Your agent finds it as the gzyms skill and runs `gzyms skill` for the guide.")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
