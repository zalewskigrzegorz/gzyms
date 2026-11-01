import Testing
@testable import GzymsCore

@Test func mochaNeonMatchesThePaletteDoc() {
    // ~/Code/dotfiles/docs/mocha-neon-palette.md
    let t = Theme.mochaNeon
    #expect([t.base, t.overlay, t.text, t.mauve, t.pink, t.lavender, t.green, t.gold, t.peach, t.red, t.sky]
        == ["#1E1E2E", "#7F849C", "#F0F0FF", "#B347FF", "#FF80BF", "#9580FF", "#50FA7B", "#FFD700", "#FF8C42", "#FF6B9D", "#8BE9FD"])
}

@Test func grayscaleHasNoColour() {
    let t = Theme.grayscale
    for hex in [t.base, t.surface, t.overlay, t.text, t.mauve, t.pink, t.lavender, t.green, t.gold, t.peach, t.red, t.sky, t.hud] {
        let rgb = Array(hex.dropFirst())
        #expect(rgb[0...1] == rgb[2...3] && rgb[2...3] == rgb[4...5], "\(hex) is not a gray")
    }
}

@Test func colourResolvesTokenOrHex() {
    #expect(Theme.mochaNeon.resolve("green") == "#50FA7B")
    #expect(Theme.grayscale.resolve("green") == Theme.grayscale.green)
    #expect(Theme.mochaNeon.resolve("#123ABC") == "#123ABC")
    #expect(Theme.mochaNeon.resolve("nope") == nil)
}

@Test func settingThemeInAnEmptyConfig() {
    #expect(settingTheme("grayscale", in: nil) == "theme = \"grayscale\"\n")
}

@Test func settingThemeReplacesTheTopLevelKeyOnly() {
    let toml = """
    # mine
    theme = "mocha-neon"

    [workspaces]
    show_empty = true
    """
    let out = settingTheme("grayscale", in: toml)
    #expect(out == toml.replacingOccurrences(of: "\"mocha-neon\"", with: "\"grayscale\""))
    #expect(loadConfig(toml: out).config.theme == .grayscale)
    #expect(loadConfig(toml: out).config.showEmpty)
}

@Test func settingThemeGoesAboveTheFirstTable() {
    // A key after [workspaces] would belong to that table, so it must go on top.
    let out = settingTheme("grayscale", in: "[workspaces]\nshow_empty = true\n")
    #expect(loadConfig(toml: out).config.theme == .grayscale)
    #expect(loadConfig(toml: out).problems == [])
}

@Test func themeByName() {
    #expect(Theme.named("mocha-neon") == .mochaNeon)
    #expect(Theme.named("grayscale") == .grayscale)
    #expect(Theme.named("solarized") == nil)
}

@Test func everyThemeReadsWell() {
    #expect((90...130).contains(Theme.all.count))
    #expect(Set(Theme.all.map(\.name)).count == Theme.all.count)  // no two share a name
    #expect(Array(Theme.all.prefix(2)) == Theme.builtIn)
    for name in ["dracula", "nord", "gruvbox_dark", "catppuccin_latte", "tokyonight", "github"] { #expect(Theme.named(name) != nil, "\(name)") }
    #expect(Theme.named("dracula")!.base == "#1E1F28")
    #expect(Theme.named("catppuccin_latte")!.isDark == false && Theme.named("nord")!.isDark)
    // The rule gen-themes.py keeps, checked again here: text 7:1 on the background, every accent 4.5:1 on it and on a chip.
    for t in Theme.all.dropFirst(2) {
        #expect(Theme.contrast(t.text, t.base) >= 7, "\(t.name) text")
        for (name, c) in [("red", t.red), ("green", t.green), ("gold", t.gold), ("peach", t.peach), ("sky", t.sky), ("mauve", t.mauve)] {
            #expect(min(Theme.contrast(c, t.base), Theme.contrast(c, t.surface)) >= 4.5, "\(t.name) \(name)")
        }
        #expect(Theme.contrast(t.overlay, t.base) >= 4.5, "\(t.name) overlay")
    }
}
