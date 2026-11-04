import Foundation
import Testing
@testable import GzymsCore

/// Everything `gzyms skill` can print, all topics together.
private let allText = skillTopics.compactMap { skillText(topic: $0) }.joined(separator: "\n")

@Test func everyNotifyFlagAndLevelIsInTheSkill() {
    for f in notifyFlags + notifySwitches { #expect(allText.contains(f), "notify \(f) missing from skill/*.md") }
    for l in NotifyLevel.allCases { #expect(allText.contains(l.rawValue), "level \(l.rawValue) missing from skill/*.md") }
}

@Test func everyCommandIsInTheSkill() {
    let commands = ["gzyms notify", "gzyms set", "gzyms unset", "gzyms theme --list", "gzyms theme ", "gzyms settings",
                    "gzyms hud", "gzyms report", "gzyms debug", "gzyms dnd", "breaks_through", "gzyms plugin list", "gzyms plugin new", "gzyms plugin add",
                    "gzyms plugin remove", "gzyms skill plugins", "gzyms skill install"]
    for c in commands { #expect(allText.contains(c), "\(c) missing from skill/*.md") }
}

@Test func everyCatalogPluginIsInTheSkill() {
    for c in pluginCatalog { #expect(allText.contains("`\(c.name)`"), "catalog plugin \(c.name) missing from skill/plugins.md") }
}

@Test func thePluginProtocolIsInTheSkill() {
    let json = ["item", "id", "text", "icon", "color", "tooltip", "remove", "menu", "tag", "detail", "separator",
                "notify", "title", "subtitle", "body", "level", "sound", "link", "event"]
        + PluginEvent.allCases.map(\.rawValue)
    for k in json { #expect(allText.contains("\"\(k)\""), "JSON key \"\(k)\" missing from skill/plugins.md") }
    let toml = ["name =", "command =", "description =", "icon =", "[[option]]", "key =", "title =", "type =", "default =",
                "choices =", "note ="] + PluginOption.Kind.allCases.map(\.rawValue)
    for k in toml { #expect(allText.contains(k), "plugin.toml \(k) missing from skill/plugins.md") }
    for e in ["GZYMS_PLUGIN", "GZYMS_OPT_", "GZYMS_OPTIONS"] { #expect(allText.contains(e), "\(e) missing from skill/plugins.md") }
}

@Test func thePluginGuidesManifestIsValid() throws {
    let text = try #require(skillText(topic: "plugins"))
    let toml = try #require(text.firstRange(of: "```toml\n").map { text[$0.upperBound...] }.flatMap { rest in rest.firstRange(of: "```").map { rest[..<$0.lowerBound] } })
    let m = try pluginManifest(toml: String(toml), folder: "prs").get()
    #expect(m.options.map(\.kind) == [.list, .choice])
}

@Test func theBuiltInTextIsTheFilesInSkill() throws {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("skill")
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".md") }
    #expect(Set(names.map { String($0.dropLast(3)) }) == Set(skillTopics + ["SKILL"]), "run scripts/gen-skill.sh")
    for n in names {
        let onDisk = try String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8)
        let topic = String(n.dropLast(3))
        #expect((topic == "SKILL" ? skillStub : skillText(topic: topic)) == onDisk, "\(n) differs from the binary: run scripts/gen-skill.sh")
    }
}

@Test func theStubSendsTheAgentToTheCLI() throws {
    #expect(skillStub.hasPrefix("---\nname: gzyms\n"))
    let description = try #require(skillStub.split(separator: "\n").first { $0.hasPrefix("description: ") })
    #expect(description.count <= 1024 + "description: ".count)  // the Agent Skills limit
    #expect(skillStub.contains("gzyms skill"))
    #expect(skillText(topic: "SKILL") == nil)  // the stub is not a topic
}

@Test func installGoesToCodexOnlyWhenItIsThere() {
    let home = URL(fileURLWithPath: "/h")
    let claude = URL(fileURLWithPath: "/h/.claude/skills/gzyms/SKILL.md")
    let codex = URL(fileURLWithPath: "/h/.agents/skills/gzyms/SKILL.md")
    #expect(skillInstallTargets(home: home, agentsExists: false, forceAgents: false) == [claude])
    #expect(skillInstallTargets(home: home, agentsExists: true, forceAgents: false) == [claude, codex])
    #expect(skillInstallTargets(home: home, agentsExists: false, forceAgents: true) == [claude, codex])
}
