/// One setting the palette can find: its tab, the section it sits in and its row's title, the name
/// `SettingsNav.target` takes to put the keyboard on it.
public struct SettingsRowRef: Sendable {
    public let tab: SettingsTab
    public let section: String
    public let title: String
    /// Searched with the title, so "battery" finds the Caffeine row.
    public let words: String
    init(_ tab: SettingsTab, _ section: String, _ title: String, _ words: String = "") {
        self.tab = tab; self.section = section; self.title = title; self.words = words
    }
}

extension SettingsTab {
    /// Every row with a control, tab by tab. A test reads SettingsView.swift and fails when a row is missing here or gone there.
    public static let rows: [SettingsRowRef] = [
        .init(.general, "Login", "Start at login", "launch boot startup"),
        .init(.general, "Workspaces", "Workspaces from", "source omniwm aerospace hyprmac spaces tiling"),
        .init(.general, "Workspaces", "Show empty workspaces"),
        .init(.general, "Workspaces", "Small bar on the notch screen", "notch compact"),
        .init(.general, "Caffeine", "Keep the display on too", "screen awake dim"),
        .init(.general, "Caffeine", "Stop on battery under", "awake"),
        .init(.general, "Config", "config.toml", "config file finder"),
        .init(.appearance, "Look", "Theme", "colors colours"),
        .init(.appearance, "Look", "CPU chart", "graph"),
        .init(.appearance, "Device icons", "Audio device icons", "speaker headphones"),
        .init(.animations, "Motion", "Animations"),
        .init(.animations, "Motion", "Follow macOS Reduce motion", "accessibility"),
        .init(.animations, "Banner", "Entry", "style drop"),
        .init(.animations, "Banner", "Speed", "fast slow"),
        .init(.animations, "Agents", "While an agent works", "border"),
        .init(.modules, "Bar", "Layout", "order pills sides modules"),
        .init(.plugins, "Plugins", "Make your own", "plugin new create"),
        .init(.agents, "Agents", "Gzyms plugin", "claude code install"),
        .init(.calendar, "Meetings", "Meeting reminders", "calendar"),
        .init(.calendar, "Meetings", "Remind me", "minutes before"),
        .init(.calendar, "Meetings", "Check before joining", "preview camera mic"),
        .init(.shortcuts, "Keyboard mode", "Leader", "key hotkey"),
        .init(.shortcuts, "Keyboard mode", "Keyboard mode", "keys hints"),
        .init(.shortcuts, "Keyboard mode", "Open", "letter banner"),
        .init(.shortcuts, "Keyboard mode", "Dismiss", "letter banner"),
        .init(.shortcuts, "Keyboard mode", "Snooze", "letter banner"),
        .init(.shortcuts, "Keyboard mode", "Second action", "letter banner alt"),
        .init(.shortcuts, "Keyboard mode", "Next waiting banner", "letter"),
        .init(.shortcuts, "Keyboard mode", "Previous waiting banner", "letter"),
        .init(.shortcuts, "Keyboard mode", "Clear a list (press twice)", "letter"),
        .init(.shortcuts, "Global", "Mute or unmute the microphone", "mic shortcut hotkey"),
        .init(.shortcuts, "macOS menu bar", "Show it while you hold", "menu"),
        .init(.sounds, "Sounds", "Sounds", "chime alert"),
        .init(.about, "Gzyms", "Automatic updates", "sparkle update"),
        .init(.about, "Gzyms", "Tutorial", "learn keys"),
        .init(.about, "Gzyms", "Website", "docs"),
        .init(.about, "Gzyms", "Source", "github code"),
        .init(.about, "Gzyms", "Changes", "whats new release notes"),
        .init(.about, "Gzyms", "Quit", "exit"),
        .init(.about, "Your logo", "Logo on the bar", "icon image"),
        .init(.debug, "Watching", "Anomaly detector", "stalls"),
        .init(.debug, "Watching", "Usage HUD", "cpu memory"),
        .init(.debug, "Watching", "Event log", "log"),
        .init(.debug, "Watching", "Flag a moment", "mark note log"),
        .init(.debug, "Something wrong?", "Report a problem", "bug zip"),
        .init(.debug, "Something wrong?", "Missing something?", "feature request idea"),
        .init(.debug, "Same notification, several apps", "Tell me about them", "duplicate"),
        .init(.hacks, "Media", "Media keys for the music player only", "browser keys"),
        .init(.hacks, "Media", "Browser tabs in the music pill", "youtube userscript"),
        .init(.hacks, "Media", "Music.app off the media keys", "keys"),
        .init(.hacks, "Media", "What plays", "now playing reader"),
        .init(.hacks, "Notifications", "Instant banners", "accessibility"),
        .init(.hacks, "Notifications", "Restart a hung Notification Center", "hang"),
        .init(.hacks, "Notifications", "Open the exact chat", "click original"),
        .init(.hacks, "Notifications", "Instant app icons", "icons"),
        .init(.hacks, "Notifications", "Notifications from other apps", "full disk"),
        .init(.hacks, "Notifications", "How these work", "docs"),
        .init(.notifications, "Sound", "Sounds", "banner"),
        .init(.notifications, "Sound", "Sound at once", "banner priority"),
        .init(.notifications, "Do Not Disturb", "Still shows", "dnd breaks through"),
        .init(.notifications, "Do Not Disturb", "Quiet while sharing the screen", "dnd share record"),
        .init(.notifications, "Lists", "Keep in the lists", "history forget"),
        .init(.notifications, "Not answered on the Mac", "Send through", "phone ntfy pushover webhook"),
        .init(.notifications, "Not answered on the Mac", "Send it", "phone after"),
        .init(.notifications, "Not answered on the Mac", "Levels", "phone"),
        .init(.notifications, "Not answered on the Mac", "Try it", "phone test push"),
    ]
}
