import Testing
@testable import GzymsCore

private let apps = ConfigTable.table(["notifications", "apps", "com.tinyspeck.slackmacgap"])

@Test func replacesValueKeepsTrailingComment() {
    let toml = "[notifications]\nsounds = true  # loud\nkeys = \"chord\"\n"
    #expect(setting("sounds", to: .bool(false), in: .table(["notifications"]), toml: toml)
        == "[notifications]\nsounds = false  # loud\nkeys = \"chord\"\n")
}

@Test func keepsHashInsideAString() {
    let toml = "[workspaces]\nname = \"a # b\"  # note\n"
    #expect(setting("name", to: .string("c"), in: .table(["workspaces"]), toml: toml)
        == "[workspaces]\nname = \"c\"  # note\n")
}

@Test func onlyTouchesItsTable() {
    let toml = "[a]\nkeys = \"x\"\n\n[notifications]\nkeys = \"chord\"\n"
    #expect(setting("keys", to: .string("tap"), in: .table(["notifications"]), toml: toml)
        == "[a]\nkeys = \"x\"\n\n[notifications]\nkeys = \"tap\"\n")
}

@Test func addsMissingKeyAtEndOfTable() {
    let toml = "[notifications]\n# mine\nsounds = true\n\n[cpu]\nchart = \"line\"\n"
    #expect(setting("keys", to: .string("tap"), in: .table(["notifications"]), toml: toml)
        == "[notifications]\n# mine\nsounds = true\nkeys = \"tap\"\n\n[cpu]\nchart = \"line\"\n")
}

@Test func addsKeyRightAfterAnEmptyHeader() {
    #expect(setting("chart", to: .string("bars"), in: .table(["cpu"]), toml: "[cpu]\n\n[x]\n")
        == "[cpu]\nchart = \"bars\"\n\n[x]\n")
}

@Test func addsMissingTableAtEnd() {
    #expect(setting("chart", to: .string("bars"), in: .table(["cpu"]), toml: "theme = \"grayscale\"\n")
        == "theme = \"grayscale\"\n\n[cpu]\nchart = \"bars\"\n")
    #expect(setting("chart", to: .string("bars"), in: .table(["cpu"]), toml: "theme = \"grayscale\"")
        == "theme = \"grayscale\"\n\n[cpu]\nchart = \"bars\"\n")
}

@Test func topLevelKeyGoesAboveTheFirstTable() {
    let out = setting("theme", to: .string("grayscale"), in: .table([]), toml: "[workspaces]\nshow_empty = true\n")
    #expect(out == "theme = \"grayscale\"\n[workspaces]\nshow_empty = true\n")
}

@Test func quotesDottedKeys() {
    let out = setting("sound", to: .bool(false), in: apps, toml: nil)
    #expect(out == "[notifications.apps.\"com.tinyspeck.slackmacgap\"]\nsound = false\n")
    // Written by hand with single quotes and spaces: the same table.
    let hand = "[ notifications . apps . 'com.tinyspeck.slackmacgap' ]\nsound = true\n"
    #expect(setting("sound", to: .bool(false), in: apps, toml: hand)
        == "[ notifications . apps . 'com.tinyspeck.slackmacgap' ]\nsound = false\n")
}

@Test func editsArrayRowByNumber() {
    let toml = """
    [[workspaces.style]]
    number = 1
    color = "green"

    [[workspaces.style]]
    number = 3
    name = "code"

    """
    let row = ConfigTable.row("workspaces.style", key: "number", value: .int(3))
    #expect(setting("color", to: .string("pink"), in: row, toml: toml)
        == toml.replacingOccurrences(of: "name = \"code\"\n", with: "name = \"code\"\ncolor = \"pink\"\n"))
    let added = setting("name", to: .string("web"), in: .row("workspaces.style", key: "number", value: .int(6)), toml: toml)
    #expect(added == toml + "\n[[workspaces.style]]\nnumber = 6\nname = \"web\"\n")
    #expect(loadConfig(toml: added).config.workspaces.first { $0.number == 6 }?.name == "web")
}

@Test func escapesStrings() {
    let name = "a \"quoted\" \\ name"
    let out = setting("name", to: .string(name), in: .row("workspaces.style", key: "number", value: .int(2)), toml: nil)
    #expect(loadConfig(toml: out).config.workspaces.first { $0.number == 2 }?.name == name)
}

@Test func removesKey() {
    let toml = "[notifications]\nsounds = false\nkeys = \"tap\"\n"
    #expect(setting("sounds", to: nil, in: .table(["notifications"]), toml: toml) == "[notifications]\nkeys = \"tap\"\n")
    #expect(setting("keys", to: nil, in: .table(["notifications"]), toml: "[notifications]\nkeys = \"tap\"\n") == "[notifications]\n")
    #expect(setting("nope", to: nil, in: .table(["notifications"]), toml: toml) == toml)
}

@Test func multiLineValueIsLeftAlone() {
    let toml = "[x]\nlist = [\n  1,\n  2,\n]\n"
    #expect(setting("list", to: .int(3), in: .table(["x"]), toml: toml) == toml)
}

@Test func emptyOrNilFileStartsFresh() {
    #expect(setting("theme", to: .string("grayscale"), in: .table([]), toml: nil) == "theme = \"grayscale\"\n")
    #expect(setting("theme", to: .string("grayscale"), in: .table([]), toml: "") == "theme = \"grayscale\"\n")
    #expect(setting("info", to: .int(6), in: .table(["notifications", "levels"]), toml: "")
        == "[notifications.levels]\ninfo = 6\n")
}

@Test func valuesReadBack() {
    var toml = setting("sounds", to: .bool(false), in: .table(["notifications"]), toml: nil)
    toml = setting("open", to: .string("e"), in: .table(["keys", "verbs"]), toml: toml)
    toml = setting("chart", to: .string("bars"), in: .table(["cpu"]), toml: toml)
    let load = loadConfig(toml: toml)
    #expect(load.problems == [])
    #expect(!load.config.notificationSounds)
    #expect(load.config.verbs.open == "e")
    #expect(load.config.cpuChart == .bars)
}

@Test func writesAnIntArrayThatReadsBack() {
    let out = setting("points", to: .ints([5, 0, -3]), in: .table(["calendar"]), toml: "[calendar]\npoints = [3, 0, -3]  # mine\n")
    #expect(out == "[calendar]\npoints = [5, 0, -3]  # mine\n")
    #expect(loadConfig(toml: out).config.meetingPoints == [5, 0, -3])
}
