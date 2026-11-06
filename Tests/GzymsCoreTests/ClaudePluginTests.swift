import Foundation
import Testing
@testable import GzymsCore

/// A fake `claude`: answers by the arguments, records every call. Nothing touches the real Claude Code.
private final class FakeClaude {
    var calls: [[String]] = []
    var answers: [String: CommandOutput]
    init(_ answers: [String: CommandOutput]) { self.answers = answers }
    func run(_ path: String, _ args: [String]) -> CommandOutput {
        calls.append(args)
        return answers[args.joined(separator: " ")] ?? CommandOutput(0)
    }
}

private func list(_ rows: String) -> CommandOutput { CommandOutput(0, out: "[\(rows)]") }
private let on = #"{"id":"gzyms@gzyms","version":"0.1.1","scope":"user","enabled":true}"#
private let disabled = #"{"id":"gzyms@gzyms","version":"0.1.1","scope":"user","enabled":false}"#
private let other = #"{"id":"agent-board@greg-mods","version":"0.1.0","enabled":true}"#

@Test func claudeIsLookedUpThroughTheLoginShellThenTheInstallerPlaces() {
    let shell = { (said: String) in { (_: String, _: [String]) in CommandOutput(0, out: said) } }
    #expect(claudeBinary(home: "/h", run: shell("/x/claude\n"), executable: { _ in true }) == "/x/claude")
    // The shell found nothing (or said something that is no path): the known places, in order.
    #expect(claudeBinary(home: "/h", run: shell(""), executable: { _ in true }) == "/h/.local/bin/claude")
    #expect(claudeBinary(home: "/h", run: shell("claude: aliased"), executable: { $0 != "/h/.local/bin/claude" }) == "/h/.claude/local/claude")
    #expect(claudeBinary(home: "/h", run: shell(""), executable: { $0 == "/usr/local/bin/claude" || $0 == "/opt/homebrew/bin/claude" }) == "/opt/homebrew/bin/claude")
    #expect(claudeBinary(home: "/h", run: shell("/gone/claude"), executable: { _ in false }) == nil)
}

@Test func theListSaysInstalledOffOrMissing() {
    #expect(claudePluginState(listJSON: "[\(other),\(on)]") == .installed("0.1.1"))
    #expect(claudePluginState(listJSON: "[\(disabled)]") == .off("0.1.1"))
    #expect(claudePluginState(listJSON: "[\(disabled),\(on)]") == .installed("0.1.1"))  // two scopes: the one that is on
    #expect(claudePluginState(listJSON: "[\(other)]") == .missing)
    #expect(claudePluginState(listJSON: "[]") == .missing)
    #expect(claudePluginState(listJSON: "Installed plugins:") == nil)
    #expect(ClaudePluginState.installed("0.1.1").line == "Installed, 0.1.1")
    #expect(ClaudePluginState.missing.line == "Not installed")
    #expect(ClaudePluginState.noClaude.line == "Claude Code not found")
}

@Test func aFailedListShowsClaudesOwnLine() {
    let c = FakeClaude(["plugin list --json": CommandOutput(1, err: "error: unknown option '--json'\nmore")])
    #expect(claudePluginState(claude: "/c", run: c.run) == .failure(AgentsError("error: unknown option '--json'")))
    #expect(claudePluginState(claude: nil, run: c.run) == .success(.noClaude))
}

@Test func installRunsTheStepsAndASecondRunIsSafe() {
    let c = FakeClaude(["plugin list --json": list(on)])
    var said: [String] = []
    #expect(changeClaudePlugin(.install, claude: "/c", run: c.run) { said.append($0) } == nil)
    #expect(c.calls == [["plugin", "marketplace", "add", "zalewskigrzegorz/gzyms-claude-plugin"], ["plugin", "install", "gzyms@gzyms"],
                        ["plugin", "list", "--json"]])
    #expect(said == ["Adding the gzyms marketplace", "Installing gzyms@gzyms"])
    // An older Claude Code exits 1 on the second run: "already" counts as done.
    let again = FakeClaude(["plugin marketplace add zalewskigrzegorz/gzyms-claude-plugin": CommandOutput(1, err: "Marketplace 'gzyms' is already added"),
                            "plugin install gzyms@gzyms": CommandOutput(1, out: "Plugin gzyms@gzyms is already installed (scope: user)"),
                            "plugin list --json": list(on)])
    #expect(changeClaudePlugin(.install, claude: "/c", run: again.run) { _ in } == nil)
}

@Test func installTurnsOnAPluginThatIsOff() {
    let c = FakeClaude(["plugin list --json": list(disabled)])
    #expect(changeClaudePlugin(.install, claude: "/c", run: c.run) { _ in } == nil)
    #expect(c.calls.last == ["plugin", "enable", "gzyms@gzyms"])
}

@Test func aFailedStepStopsWithClaudesLine() {
    let c = FakeClaude(["plugin marketplace add zalewskigrzegorz/gzyms-claude-plugin":
                            CommandOutput(1, out: "Cloning…\n", err: "✘ Failed to add marketplace: git clone failed\n  details")])
    #expect(changeClaudePlugin(.install, claude: "/c", run: c.run) { _ in } == AgentsError("✘ Failed to add marketplace: git clone failed"))
    #expect(c.calls.count == 1)
    // From another source is no "already done".
    let clash = FakeClaude(["plugin marketplace add zalewskigrzegorz/gzyms-claude-plugin":
                                CommandOutput(1, err: "Marketplace gzyms is already added from a different source (x/y).")])
    #expect(changeClaudePlugin(.install, claude: "/c", run: clash.run) { _ in }?.message.contains("different source") == true)
    // Nothing on either stream.
    let mute = FakeClaude(["plugin install gzyms@gzyms": CommandOutput(2)])
    #expect(changeClaudePlugin(.install, claude: "/c", run: mute.run) { _ in } == AgentsError("claude exited with 2."))
}

@Test func removeUninstallsOnlyWhatIsThereAndKeepsTheMarketplace() {
    let c = FakeClaude(["plugin list --json": list(on)])
    #expect(changeClaudePlugin(.remove, claude: "/c", run: c.run) { _ in } == nil)
    #expect(c.calls == [["plugin", "list", "--json"], ["plugin", "uninstall", "gzyms@gzyms"]])
    let gone = FakeClaude(["plugin list --json": list(other)])
    #expect(changeClaudePlugin(.remove, claude: "/c", run: gone.run) { _ in } == nil)
    #expect(gone.calls == [["plugin", "list", "--json"]])
}

@Test func noClaudeDoesNothingAndSaysTheFix() {
    var ran = false
    #expect(changeClaudePlugin(.install, claude: nil, run: { _, _ in ran = true; return CommandOutput(0) }) { _ in } == AgentsError(claudeMissing))
    #expect(!ran)
}
