import Foundation

// `gzyms skill`: how to use and extend Gzyms, written for coding agents. The texts are skill/*.md at the repo root,
// built in by scripts/gen-skill.sh (Skill.gen.swift), so they always match the binary that prints them.

/// What `gzyms skill <topic>` prints; "guide" is the default.
public let skillTopics = skillFiles.keys.filter { $0 != "SKILL" }.sorted()

public func skillText(topic: String) -> String? { topic == "SKILL" ? nil : skillFiles[topic] }

/// The SKILL.md `gzyms skill install` writes: a stub that sends the agent to `gzyms skill`, so it never goes stale.
public var skillStub: String { skillFiles["SKILL", default: ""] }

/// Claude Code always; Codex when `~/.agents` is there or asked for.
public func skillInstallTargets(home: URL, agentsExists: Bool, forceAgents: Bool) -> [URL] {
    let dirs = [".claude"] + (agentsExists || forceAgents ? [".agents"] : [])
    return dirs.map { home.appendingPathComponent("\($0)/skills/gzyms/SKILL.md") }
}
