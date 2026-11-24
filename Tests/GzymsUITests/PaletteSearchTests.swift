import AppKit
import GzymsCore
import SwiftUI
import Testing
@testable import GzymsUI

private func flag(_ q: String) -> [PaletteItem] { [PaletteItem(id: "mark", title: "Flag this moment: \(q)", kind: "Action") {}] }

/// Greg, 2026-11-24: "Flag this moment" runs only after a key moved onto it, never from the default selection.
@MainActor @Test func flagRowAloneIsNotSelectedUntilAKeyMovesOntoIt() {
    let s = PaletteState()
    s.items = [PaletteItem(id: "a", title: "Sounds", kind: "Settings") {}]
    s.last = flag
    s.query = "banner looked off"
    #expect(s.shown.map(\.id) == ["mark"])
    #expect(s.current == nil)
    s.move(1)
    #expect(s.current?.id == "mark")
}

@MainActor @Test func flagRowUnderMatchesNeedsKeysToReach() {
    let s = PaletteState()
    s.items = [PaletteItem(id: "a", title: "Sounds", kind: "Settings") {}, PaletteItem(id: "b", title: "Sound at once", kind: "Notifications") {}]
    s.last = flag
    s.query = "sound"
    #expect(s.current?.id == "a")
    s.move(1)
    #expect(s.current?.id == "b")
    s.move(1)
    #expect(s.current?.id == "mark")
    s.query = "sounds"
    #expect(s.current?.id == "a")
}

/// A palette with every kind of row: tabs, a setting, actions, a plugin row, a device, a meeting, an agent.
@MainActor @Test func paletteWithMixedKinds() {
    let s = PaletteState()
    s.items = [PaletteItem(id: "t", title: "Notifications", kind: "Settings", tier: 0) {},
               PaletteItem(id: "r", title: "Sound at once", kind: "Notifications", words: "Sound banner priority settings") {},
               PaletteItem(id: "o", title: "Output: AirPods Pro", kind: "Audio", words: "speaker sound") {},
               PaletteItem(id: "p", title: "Fix banner sound on wake", kind: "GitHub PRs", words: "#31 CI passed", tier: 2, alt: {}) {},
               PaletteItem(id: "m", title: "Join Standup in 25 min", kind: "Meeting", words: "meeting call") {},
               PaletteItem(id: "g", title: "gzyms-palette", kind: "Agent", words: "gzyms tuios") {},
               PaletteItem(id: "x", title: "Sounds", kind: "Settings", tier: 0) {}]
    s.last = flag
    s.query = "sound"
    // Titles first, then the device that has "sound" only as a keyword.
    #expect(s.shown.map(\.id) == ["x", "r", "p", "o", "mark"])
    s.move(2)
    preview(PaletteView(state: s) { _ in }.themed(.mochaNeon), "palette-mixed")
}

/// Every row with a control in SettingsView is in `SettingsTab.rows` and every entry there still exists, read from
/// the source, so a renamed row cannot leave the palette pointing nowhere.
@Test func settingsIndexMatchesTheRowsInSettingsView() throws {
    let source = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Sources/GzymsUI/SettingsView.swift"), encoding: .utf8)
    let tabs: [String: SettingsTab] = ["GeneralTab": .general, "AppearanceTab": .appearance, "AnimationsTab": .animations, "ThemesTab": .themes,
                                       "NotificationsTab": .notifications, "AppsTab": .apps, "ModulesTab": .modules, "PluginsTab": .plugins,
                                       "CalendarTab": .calendar, "AgentsTab": .agents, "AudioTab": .audio, "SoundsTab": .sounds,
                                       "ShortcutsTab": .shortcuts, "HacksTab": .hacks, "DebugTab": .debug, "AboutTab": .about]
    // Rows without a control: empty states, license lines, a heading over the Focus switches.
    let skip: Set = ["No calendars yet", "No audio devices found", "None seen", "Synced with macOS Focus", "armageddon",
                     "Gzyms", "TOMLDecoder", "Sparkle", "NotificationNanny"]
    var found: [String] = [], tab: SettingsTab?
    for line in source.split(separator: "\n") {
        if let m = line.firstMatch(of: /^(?:private )?struct (\w+)/) { tab = tabs[String(m.1)] }
        guard let tab else { continue }
        for m in line.matches(of: /Row\(title: "([^"\\]+)"/) where !skip.contains(String(m.1)) { found.append("\(tab.rawValue): \(m.1)") }
    }
    let indexed = SettingsTab.rows.map { "\($0.tab.rawValue): \($0.title)" }
    #expect(Set(found).subtracting(indexed).sorted() == [], "add these to SettingsTab.rows")
    #expect(Set(indexed).subtracting(found).subtracting(["shortcuts: Leader"]).sorted() == [], "gone from SettingsView")
    #expect(source.contains("Row(title: \"Leader\""))
}

/// The palette puts the keyboard on one row: its control takes `current`, Enter then acts on that row.
@MainActor @Test func settingsNavTargetLandsOnTheRow() async {
    var written: [String] = []
    let nav = SettingsNav()
    nav.target = "Stop on battery under"
    let view = SettingsView(tab: .constant(.general), config: .defaults, problems: [], broken: false, apps: [], devices: [],
                            actions: SettingsActions { key, _, _ in written.append(key) })
        .environment(\.settingsNav, nav).themed(.mochaNeon).frame(width: 1000, height: 900)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
    host.layoutSubtreeIfNeeded()
    for _ in 0..<20 where nav.current == nil { try? await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
    #expect(nav.target == nil)
    #expect(nav.current != nil)
    nav.choose()
    #expect(written == ["battery_below"])
}

@MainActor @Test func settingsNavTargetOpensAnAppDrawer() async {
    let nav = SettingsNav()
    nav.target = "app:com.tinyspeck.slackmacgap"
    let apps = [SeenApp(id: "com.tinyspeck.slackmacgap", name: "Slack", icon: nil)]
    let host = NSHostingView(rootView: SettingsView(tab: .constant(.apps), config: .defaults, problems: [], broken: false, apps: apps, devices: [],
                                                    actions: SettingsActions { _, _, _ in })
        .environment(\.settingsNav, nav).themed(.mochaNeon).frame(width: 1000, height: 900))
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
    let before = nav.frames.count
    host.layoutSubtreeIfNeeded()
    for _ in 0..<20 where nav.target != nil { try? await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
    #expect(nav.target == nil)
    // The drawer's controls registered next to the list's one row.
    #expect(nav.frames.count > before + 1)
}
