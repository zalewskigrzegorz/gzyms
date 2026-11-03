import Foundation
import Testing
@testable import GzymsCore

@Test func manifestNeedsACommand() throws {
    let m = try pluginManifest(toml: "name = \"PR watch\"\ncommand = \"./run\"\nicon = \"arrow.triangle.pull\"", folder: "prs").get()
    #expect(m == PluginManifest(folder: "prs", name: "PR watch", command: "./run", icon: "arrow.triangle.pull"))
    #expect(try pluginManifest(toml: "command = \"x\"", folder: "bare").get().name == "bare")  // the folder names it
    #expect((try? pluginManifest(toml: "name = \"x\"", folder: "f").get()) == nil)
    #expect((try? pluginManifest(toml: "name = ", folder: "f").get()) == nil)
}

@Test func linesBecomeMessages() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(pluginMessage(#"{"item":{"id":"b","text":"✓ 12","icon":"hammer","color":"green"}}"#, plugin: "ci", now: now)
        == .item(PluginItem(id: "b", text: "✓ 12", icon: "hammer", color: "green")))
    #expect(pluginMessage(#"{"item":{"id":"b","remove":true}}"#, plugin: "ci", now: now) == .removeItem("b"))
    guard case .notify(let n) = pluginMessage(#"{"notify":{"id":"d","title":"Deploy done","level":"error"}}"#, plugin: "ci", now: now)
    else { Issue.record("not a notify"); return }
    #expect(n.id == "plugin:ci:d" && n.level == .error && n.title == "Deploy done")
    #expect(!n.hasAlt)
    // A named second action without a link goes back to the plugin; with one it opens the link.
    guard case .notify(let a) = pluginMessage(#"{"notify":{"id":"a","title":"Agent waits","alt_label":"Open in agent"}}"#, plugin: "ag", now: now),
          case .notify(let l) = pluginMessage(#"{"notify":{"id":"l","title":"PR","alt_link":"https://x","alt_label":"Diff"}}"#, plugin: "ag", now: now)
    else { Issue.record("not a notify"); return }
    #expect(a.altLabel == "Open in agent" && a.altLink == nil && a.hasAlt)
    #expect(l.altLabel == "Diff" && l.altLink == "https://x" && l.hasAlt)
    #expect(pluginMessage(#"{"item":{"id":"b"}}"#, plugin: "ci", now: now) == nil)   // no text
    #expect(pluginMessage(#"{"notify":{"body":"x"}}"#, plugin: "ci", now: now) == nil) // no title
    #expect(pluginMessage("hello", plugin: "ci", now: now) == nil)
}

@Test func eventsAreOneJSONLine() throws {
    let e = pluginEventLine(.rightClick, id: "a\"b")
    #expect(!e.contains("\n"))
    let back = try JSONDecoder().decode([String: String].self, from: Data(e.utf8))
    #expect(back == ["event": "right_click", "id": "a\"b"])
}

@Test func anItemCanCarryAList() {
    let line = ##"{"item":{"id":"prs","text":"✗ 1","menu":[{"id":"pr:1","tag":"fix CI","color":"peach","text":"#1 title","detail":"💬 2"},{"separator":true},{"text":"no data yet"}]}}"##
    guard case .item(let i) = pluginMessage(line, plugin: "pr", now: Date()) else { Issue.record("not an item"); return }
    #expect(i.menu == [PluginRow(id: "pr:1", text: "#1 title", tag: "fix CI", color: "peach", detail: "💬 2"),
                       PluginRow(separator: true), PluginRow(text: "no data yet")])
}

@Test func scaffoldIsAValidPlugin() throws {
    let s = pluginScaffold(folder: "hello")
    let m = try pluginManifest(toml: s.manifest, folder: "hello").get()
    #expect(m.command == "./plugin.sh" && m.options.map(\.key) == ["label"])
    #expect(s.script.contains("GZYMS_OPT_LABEL"))
    #expect(s.script.hasPrefix("#!/bin/bash"))
}

@Test func manifestOptionsBecomeAFormAndAnEnvironment() throws {
    let toml = """
    command = "./run"
    [[option]]
    key = "repos"
    title = "Repos"
    type = "list"
    default = ["a/b"]
    [[option]]
    key = "sound"
    type = "toggle"
    default = true
    [[option]]
    key = "mode"
    type = "choice"
    choices = ["mine", "team"]
    default = "mine"
    """
    let m = try pluginManifest(toml: toml, folder: "prs").get()
    #expect(m.options.map(\.key) == ["repos", "sound", "mode"])
    #expect(m.options[0] == PluginOption(key: "repos", title: "Repos", kind: .list, defaultValue: .strings(["a/b"])))
    #expect(m.options[2].choices == ["mine", "team"] && m.options[1].title == "sound")
    let env = pluginEnvironment(m, values: ["repos": .strings(["x/y", "z/w"]), "sound": .bool(false)])
    #expect(env["GZYMS_OPT_REPOS"] == "x/y\nz/w" && env["GZYMS_OPT_SOUND"] == "false" && env["GZYMS_OPT_MODE"] == "mine")
    #expect(env["GZYMS_OPTIONS"] == #"{"mode":"mine","repos":["x\/y","z\/w"],"sound":false}"#)
    #expect(env["GZYMS_PLUGIN"] == "prs")
    // a bad key or type names the problem instead of running a half-read plugin
    #expect((try? pluginManifest(toml: "command = \"x\"\n[[option]]\nkey = \"Bad Key\"", folder: "f").get()) == nil)
    #expect((try? pluginManifest(toml: "command = \"x\"\n[[option]]\nkey = \"k\"\ntype = \"slider\"", folder: "f").get()) == nil)
}

@Test func configKeepsAPluginsOptions() {
    let l = loadConfig(toml: "[plugins.prs]\nenabled = false\nrepos = [\"a/b\"]\nsound = true")
    #expect(l.config.disabledPlugins == ["prs"])
    #expect(l.config.pluginOptions["prs"] == ["repos": .strings(["a/b"]), "sound": .bool(true)])
}

@Test func pluginsCanBeTurnedOff() {
    let l = loadConfig(toml: "[plugins.prs]\nenabled = false\n[plugins.ci]\nenabled = true")
    #expect(l.config.disabledPlugins == ["prs"])
    #expect(l.problems.isEmpty)
}
