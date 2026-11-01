import Testing
@testable import GzymsCore

@Test func shortcutRoundTrips() {
    for key in Shortcut.keyCodes.keys {
        let s = Shortcut(ctrl: true, alt: true, key: key)
        #expect(Shortcut(s.text) == s)
        #expect(Shortcut.key(forCode: s.keyCode) == key)
    }
    #expect(Shortcut("ctrl+alt+m")?.symbol == "⌃⌥M")
    #expect(Shortcut("Cmd + Shift + 1")?.text == "shift+cmd+1")
}

@Test func shortcutNeedsAModifierAndAKnownKey() {
    #expect(Shortcut("m") == nil)
    #expect(Shortcut("shift+m") == nil)
    #expect(Shortcut("ctrl+alt+f18") == nil)
    #expect(Shortcut("hyper+m") == nil)
    #expect(Shortcut("ctrl+m")?.clashesWithHyprMac == true)
    #expect(Shortcut("ctrl+alt+m")?.clashesWithHyprMac == false)
    #expect(GzymsConfig.defaults.micShortcut == Shortcut("ctrl+alt+m"))
    #expect(loadConfig(toml: "[shortcuts]\nmic_mute = \"off\"").config.micShortcut == nil)
    #expect(loadConfig(toml: "[shortcuts]\nmic_mute = \"m\"").problems.count == 1)
}
