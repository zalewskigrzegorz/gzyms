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
    #expect(pluginMessage(#"{"dismiss":"agent-3"}"#, plugin: "agents", now: now) == .dismiss("plugin:agents:agent-3"))
    #expect(pluginMessage(#"{"dismiss":""}"#, plugin: "agents", now: now) == nil)
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

// MARK: - A pill that cannot get its data

@Test func anItemCanSayItFailedAndWhenItWillSpeakAgain() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(pluginMessage(#"{"item":{"id":"p","text":"3","error":"gh is logged out","expect":120}}"#, plugin: "gh", now: now)
        == .item(PluginItem(id: "p", text: "3", error: "gh is logged out", expect: 120)))
    // An empty error and a promise of 0 seconds mean nothing.
    #expect(pluginMessage(#"{"item":{"id":"p","text":"3","error":"","expect":0}}"#, plugin: "gh", now: now)
        == .item(PluginItem(id: "p", text: "3")))
}

@Test func aPillFailsWhenItSaysSoWhenTheProcessIsGoneOrWhenItGoesQuiet() {
    let t0 = Date(timeIntervalSince1970: 1000)
    let fine = HeldItem(item: PluginItem(id: "p", text: "3", expect: 60), heard: t0)
    #expect(pluginFailure(fine, exit: nil, now: t0.addingTimeInterval(60)) == nil)
    // Silent for twice what it promised and half a minute: failed, since the last word.
    #expect(pluginFailure(fine, exit: nil, now: t0.addingTimeInterval(150)) == nil)
    #expect(pluginFailure(fine, exit: nil, now: t0.addingTimeInterval(151))?.since == t0)
    // A plugin that promised nothing may be quiet for ever.
    let quiet = HeldItem(item: PluginItem(id: "p", text: "3"), heard: t0)
    #expect(pluginFailure(quiet, exit: nil, now: t0.addingTimeInterval(86400)) == nil)
    // Its own word, and a dead process: both fail every pill it left.
    let said = HeldItem(item: PluginItem(id: "p", text: "3", error: "no network"), heard: t0, errorSince: t0.addingTimeInterval(-30))
    #expect(pluginFailure(said, exit: nil, now: t0) == PluginFailure(message: "no network", since: t0.addingTimeInterval(-30)))
    let gone = PluginFailure(message: "stopped", since: t0)
    #expect(pluginFailure(quiet, exit: gone, now: t0) == gone)
}

@Test func anErrorKeepsItsStartWhileItLastsAndGoesWithTheNextGoodLine() {
    let t0 = Date(timeIntervalSince1970: 1000)
    let bad = PluginItem(id: "p", text: "3", error: "no network"), good = PluginItem(id: "p", text: "4")
    let h1 = hold(bad, previous: hold(good, previous: nil, now: t0), now: t0.addingTimeInterval(10))
    #expect(h1.errorSince == t0.addingTimeInterval(10))
    let h2 = hold(PluginItem(id: "p", text: "3", error: "still no network"), previous: h1, now: t0.addingTimeInterval(70))
    #expect(h2.errorSince == t0.addingTimeInterval(10) && h2.heard == t0.addingTimeInterval(70))
    let h3 = hold(good, previous: h2, now: t0.addingTimeInterval(130))
    #expect(h3.errorSince == nil && pluginFailure(h3, exit: nil, now: t0.addingTimeInterval(130)) == nil)
}


// MARK: - Popup blocks

private func menu(_ rows: String) -> [PluginRow] {
    guard case .item(let i) = pluginMessage(#"{"item":{"id":"x","text":"x","menu":["# + rows + #"]}}"#, plugin: "p", now: Date()) else { return [] }
    return i.menu ?? []
}

@Test func blocksAreParsed() {
    let rows = menu(#"""
    {"value":"4.0613","color":"green","unit":"PLN per USD","deltas":[{"label":"1 d","text":"+0.0437","color":"green"}]},
    {"chart":{"values":[3.9,4.0,4.06],"labels":["9 Oct","1 Nov","20 Nov"],"line":{"value":4.0,"label":"threshold"},"color":"sky"}},
    {"stats":[{"label":"min","value":"3.8827"}]},
    {"text":"trawy","meter":{"value":4,"max":5},"color":"peach","detail":"wysokie"}
    """#)
    #expect(rows.count == 4)
    #expect(rows[0].headline == RowHeadline(value: "4.0613", unit: "PLN per USD", deltas: [RowChip(label: "1 d", text: "+0.0437", color: "green")]))
    #expect(rows[0].color == "green")
    #expect(rows[1].chart == RowChart(values: [3.9, 4.0, 4.06], labels: ["9 Oct", "1 Nov", "20 Nov"], kind: .line,
                                      line: RowRule(value: 4.0, label: "threshold"), color: "sky"))
    #expect(rows[2].stats == [RowStat(label: "min", value: "3.8827", color: nil)])
    #expect(rows[3].meter == RowMeter(value: 4, max: 5))
    #expect(rows[3].text == "trawy" && rows[3].detail == "wysokie" && rows[3].color == "peach")
}

@Test func aNullValueDropsOnlyThatPoint() {
    #expect(menu(#"{"chart":{"values":[1,null,3]}}"#).first?.chart?.values == [1, 3])
}

@Test func aChartWithFewerThanTwoValuesIsLeftOut() {
    let rows = menu(#"{"text":"a"},{"chart":{"values":[1]}},{"text":"b"}"#)
    #expect(rows.map(\.text) == ["a", "b"])
}

@Test func wrongLabelCountDropsLabels() {
    let c = menu(#"{"chart":{"values":[1,2,3],"labels":["a","b"]}}"#).first?.chart
    #expect(c?.values == [1, 2, 3] && c?.labels == nil)
}

@Test func meterIsClamped() {
    #expect(menu(#"{"text":"a","meter":{"value":9,"max":5}}"#).first?.meter == RowMeter(value: 5, max: 5))
    #expect(menu(#"{"text":"a","meter":{"value":-1,"max":50}}"#).first?.meter == RowMeter(value: 0, max: 12))
    #expect(menu(#"{"text":"a","meter":{"value":1,"max":0}}"#).first?.meter == RowMeter(value: 1, max: 1))
}

@Test func unknownChartKindFallsBackToLine() {
    #expect(menu(#"{"chart":{"values":[1,2],"kind":"pie"}}"#).first?.chart?.kind == .line)
    #expect(menu(#"{"chart":{"values":[1,2],"kind":"bars"}}"#).first?.chart?.kind == .bars)
}

@Test func numbersWhereTextIsExpectedAreTakenAsText() {
    let rows = menu(#"{"value":15,"deltas":[{"label":"7 d","text":2}]},{"stats":[{"label":"min","value":3.88}]}"#)
    #expect(rows.first?.headline == RowHeadline(value: "15", deltas: [RowChip(label: "7 d", text: "2")]))
    #expect(rows.last?.stats == [RowStat(label: "min", value: "3.88")])
}

@Test func aBadBlockDropsOnlyItsRow() {
    let rows = menu(#"{"text":"a"},{"text":"m","meter":{"value":"x","max":5}},{"text":"b"}"#)
    #expect(rows.map(\.text) == ["a", "b"])
    #expect(menu(#"{"chart":{"values":[1,2],"labels":[2025,2026]}}"#).first?.chart?.labels == ["2025", "2026"])
}

@Test func rowAndNoteCarryABranch() {
    let rows = menu(#"{"id":"pr:1","text":"a","branch":"O/R@feat/x"},{"id":"pr:2","text":"b","branch":"nope"}"#)
    #expect(rows.map(\.text) == ["a", "b"])
    #expect(rows[0].branch == RepoBranch(repo: "o/r", branch: "feat/x") && rows[1].branch == nil)
    guard case .notify(let n)? = pluginMessage(#"{"notify":{"title":"CI failed","branch":"o/r@b"}}"#, plugin: "p", now: Date()) else { Issue.record("no note"); return }
    #expect(n.branch == RepoBranch(repo: "o/r", branch: "b"))
}

@Test func aLongChartKeepsTheNewestPoints() {
    let vs = (1...500).map(String.init).joined(separator: ",")
    let c = menu(#"{"chart":{"values":["# + vs + #"]}}"#).first?.chart
    #expect(c?.values.count == 400 && c?.values.last == 500)
}
