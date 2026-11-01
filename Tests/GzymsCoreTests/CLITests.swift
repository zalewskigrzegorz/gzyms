import Foundation
import Testing
@testable import GzymsCore

@Test func noArgumentsStartsTheBar() {
    #expect(cliProblem([]) == nil)
}

@Test func everyKnownCommandPasses() {
    for c in cliCommands { #expect(cliProblem([c, "x"]) == nil, "\(c)") }
    #expect(cliProblem(["--version"]) == nil)
}

@Test func aTypoIsAnErrorWithTheClosestCommands() throws {
    let text = try #require(cliProblem(["hek"]))
    #expect(text.contains("unknown command \"hek\""))
    let hint = try #require(text.split(separator: "\n").first { $0.hasPrefix("did you mean: ") })
    #expect(hint.contains("hud"))
    #expect(text.contains("gzyms help"))
}

@Test func somethingFarOffGetsOnlyTheList() throws {
    let text = try #require(cliProblem(["frobnicate"]))
    #expect(!text.contains("did you mean"))
    #expect(text.contains("gzyms help"))
}

@Test func anUnknownFlagIsAnError() {
    #expect(cliProblem(["--hep"]) != nil)
}

@Test func helpIsNeverAnUnknownCommand() {
    for a in [["help"], ["-h"], ["--help"], ["help", "notify"], ["completions", "nu"]] { #expect(cliProblem(a) == nil, "\(a)") }
}

@Test func helpRequestsFindTheirCommand() {
    #expect(helpTopic(["help"]) == "")
    #expect(helpTopic(["-h"]) == "")
    #expect(helpTopic(["--help"]) == "")
    #expect(helpTopic(["help", "notify"]) == "notify")
    #expect(helpTopic(["notify", "--help"]) == "notify")
    #expect(helpTopic(["notify", "--title", "-h"]) == nil)  // a value, not a request
    #expect(helpTopic([]) == nil)
}

@Test func helpListsEveryCommandButTheDebugOnes() throws {
    let text = try #require(helpText(""))
    for c in cliTable { #expect(text.contains("  \(c.name) ") != c.debug, "\(c.name)") }
    #expect(text.contains("gzyms skill"))
    #expect(helpText("nope") == nil)
}

@Test func notifyHelpHasEveryFlagFromTheGuide() throws {
    let text = try #require(helpText("notify"))
    for f in notifyFlags + notifySwitches { #expect(text.contains(" \(f) ") || text.contains(" \(f)\n"), "\(f)") }
    #expect(!text.contains("|"))
}

@Test func everyShellGetsEveryCommandAndNotifyFlag() throws {
    for shell in completionShells {
        let s = try #require(completionScript(shell, extra: ["settings": ["general", "debug"]]))
        for c in cliTable where !c.debug { #expect(s.contains(c.name), "\(shell): \(c.name)") }
        for f in notifyFlags + notifySwitches { #expect(s.contains(f), "\(shell): \(f)") }
        #expect(s.contains("debug"), "\(shell): settings tabs")
        #expect(!s.contains("untested-macos"), "\(shell): debug command")
    }
    #expect(completionScript("cmd") == nil)
}

@Test func completionsInstallPerShell() {
    let home = URL(fileURLWithPath: "/h")
    #expect(completionInstallTarget(shell: "nu", home: home) == .file(URL(fileURLWithPath: "/h/.config/nushell/autoload/gzyms.nu")))
    #expect(completionInstallTarget(shell: "nu", home: home, nuAutoload: URL(fileURLWithPath: "/n")) == .file(URL(fileURLWithPath: "/n/gzyms.nu")))
    #expect(completionInstallTarget(shell: "fish", home: home) == .file(URL(fileURLWithPath: "/h/.config/fish/completions/gzyms.fish")))
    guard case .rcLine(let rc, let line)? = completionInstallTarget(shell: "zsh", home: home) else { Issue.record("zsh"); return }
    #expect(rc.path == "/h/.zshrc")
    #expect(line.contains("gzyms completions zsh"))
    #expect(completionInstallTarget(shell: "tcsh", home: home) == nil)
}

@Test func theRCLineIsAddedOnce() throws {
    let once = try #require(addingRCLine("source x", to: "export A=1"))
    #expect(once == "export A=1\n\n# gzyms tab completion\nsource x\n")
    #expect(addingRCLine("source x", to: once) == nil)
    #expect(addingRCLine("source x", to: "") == "\n# gzyms tab completion\nsource x\n")
}

@Test func nuShowsWhatEachCommandAndNotifyFlagDoes() throws {
    let s = try #require(completionScript("nu"))
    for c in cliTable where !c.debug { #expect(s.contains("description: \"\(c.summary)\""), "\(c.name)") }
    #expect(s.contains("--body(-b): string  # The text"))
    #expect(s.contains("--compact(-c)  # The small island with only the app's icon"))
}

@Test func shortFlagsAreWrittenOut() {
    #expect(expandShortFlags(["-v"]) == ["--version"])
    #expect(expandShortFlags(["theme", "-l"]) == ["theme", "--list"])
    #expect(expandShortFlags(["skill", "install", "-a", "-y"]) == ["skill", "install", "--agents", "--yes"])
    #expect(expandShortFlags(["completions", "install", "nu", "-y"]) == ["completions", "install", "nu", "--yes"])
    #expect(expandShortFlags(["notify", "--body", "-t"]) == ["notify", "--body", "-t"])  // notify reads its own
    #expect(expandShortFlags(["set", "-l", "x"]) == ["set", "-l", "x"])
}

@Test func everyShortFlagIsOneLetterAndUniquePerCommand() {
    for (cmd, map) in cliShortFlags {
        for (short, long) in map { #expect(short.count == 2 && short.hasPrefix("-") && long.hasPrefix("--"), "\(cmd) \(short)") }
        #expect(Set(map.values).count == map.count, "\(cmd)")
    }
    #expect(cliShortFlags["notify"]?.values.contains("--sound") == false)
    #expect(cliShortFlags["notify"]?.values.contains("--screen") == false)
}

@Test func helpShowsTheShortForms() throws {
    let text = try #require(helpText("notify"))
    #expect(text.contains("-t, --title"))
    #expect(text.contains("    --sound"))
    #expect(try #require(helpText("")).contains("-v, --version"))
}
