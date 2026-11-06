import AppKit
import GzymsCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Sendable {
    case general, appearance, animations, themes, notifications, apps, modules, plugins, calendar, agents, sounds, shortcuts, permissions, hacks, debug, about
    public var title: String { self == .modules ? "Order" : rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// An app on the Notifications list: seen sending something, or set up by hand.
public struct SeenApp: Equatable {
    public var id: String, name: String
    public var icon: NSImage?
    /// Its macOS notification settings; nil = not read (no Full Disk Access, the switches in Hacks off, a plugin).
    public var mac: NCAppSettings?
    public init(id: String, name: String, icon: NSImage?, mac: NCAppSettings? = nil) { self.id = id; self.name = name; self.icon = icon; self.mac = mac }
}

/// What Settings → Debug shows about apps that sent the same notification.
public struct DuplicatesState: Equatable {
    public var groups: [DuplicateGroup] = []
    /// Gzyms posts a notification for a new pair of apps.
    public var warningsOn = true
    public init(groups: [DuplicateGroup] = [], warningsOn: Bool = true) { self.groups = groups; self.warningsOn = warningsOn }
}

/// What the panel can ask the app to do. Every setting goes through `write`, which edits one line of `config.toml`.
public struct SettingsActions {
    public var write: (String, TOMLValue?, ConfigTable) -> Void
    public var chooseApp: () -> Void = {}
    /// Picks an image for `[bar] logo`.
    public var chooseLogo: () -> Void = {}
    /// A plugin folder: show it in Finder, or move it to the Trash.
    public var revealPlugin: (String) -> Void = { _ in }
    public var removePlugin: (String) -> Void = { _ in }
    /// A ready plugin from the catalog, by name.
    public var addPlugin: (String) -> Void = { _ in }
    /// Backs up the user's edited catalog plugin and puts the catalog version in its place.
    public var updatePlugin: (String) -> Void = { _ in }
    /// A plugin folder from disk, dropped or chosen: copied into the plugins folder. Returns what went wrong, if anything.
    public var installPlugin: (URL) -> String? = { _ in nil }
    public var choosePlugin: () -> Void = {}
    public var dropApp: (URL) -> Void = { _ in }
    public var revealConfig: () -> Void = {}
    public var openNotificationSettings: () -> Void = {}
    /// One app's own page in System Settings → Notifications, by bundle id.
    public var openAppNotifications: (String) -> Void = { _ in }
    /// The apps seen sending the same notification, read fresh while the Debug tab is open.
    public var duplicates: () -> DuplicatesState = { DuplicatesState() }
    public var setDuplicateWarnings: (Bool) -> Void = { _ in }
    /// Takes a group off that list; its pairs get a notification again if they come back.
    public var forgetDuplicates: ([String]) -> Void = { _ in }
    /// Takes an app off the Apps list: forgets it was seen and drops its rule.
    public var forgetApp: (String) -> Void = { _ in }
    /// Opens these apps' macOS pages one after another, with a helper next to System Settings.
    public var setUpApps: ([String]) -> Void = { _ in }
    /// Sends a test to `[notifications.phone] url`; the line says how it went.
    public var playSound: (SoundEvent) -> Void = { _ in }
    /// Picks an audio file for the event and writes it to `[sounds]`.
    public var chooseSound: (SoundEvent) -> Void = { _ in }
    public var testPhone: (@escaping @MainActor (String) -> Void) -> Void = { _ in }
    /// The height the panel needs to show everything; it grows up to the whole screen, then scrolls.
    public var height: (CGFloat) -> Void = { _ in }
    public var close: () -> Void = {}
    public var openGrant: (Grant) -> Void = { _ in }
    public var restart: () -> Void = {}
    public var showHUD: () -> Void = {}
    public var openLog: () -> Void = {}
    /// Makes the report; returns where it went (nil = failed, see the log).
    public var report: () -> URL? = { nil }
    public var requestFeature: () -> Void = {}
    /// The login item as macOS sees it. nil: the dev install, which launchd starts (install-dev.sh).
    public var loginItem: () -> LoginItemStatus? = { .enabled }
    public var openLoginItems: () -> Void = {}
    public var version = "dev"
    /// Sparkle has a feed to ask; without it the button stays out.
    public var canCheckForUpdates = false
    public var checkForUpdates: () -> Void = {}
    /// Installed with `brew install --cask gzyms`: Homebrew updates the app, Sparkle stays off unless turned on.
    public var homebrew = false
    /// A newer version the Homebrew install found (Settings → About shows how to get it).
    public var newVersion: () -> String? = { nil }
    public var quit: () -> Void = {}
    public var openURL: (String) -> Void = { _ in }
    /// A shortcut recorder is listening: the keyboard tap stands aside.
    public var recording: (Bool) -> Void = { _ in }
    /// What Settings → Hacks shows, read fresh every 2 s while that tab is open.
    public var hacks: () -> HacksState = { HacksState() }
    /// `killall NotificationCenter`; macOS starts it again.
    public var restartNotificationCenter: () -> Void = {}
    /// Quits a running app by bundle id (Music.app, which takes the media keys).
    public var quitApp: (String) -> Void = { _ in }
    public init(write: @escaping (String, TOMLValue?, ConfigTable) -> Void) { self.write = write }
}

/// The settings panel's content. Holds no settings of its own: it draws `config` and writes changes back.
public struct SettingsView: View {
    @Binding var tab: SettingsTab
    let config: GzymsConfig
    let problems: [String]
    let broken: Bool
    let apps: [SeenApp]
    let devices: [String]
    /// Workspace names come from HyprMac (Greg, 2026-10-31); Gzyms only colours them.
    let workspaceNames: [Int: String]
    let grants: [GrantState]
    let calendars: [CalendarInfo]
    let logo: NSImage?
    /// false while the panel is put away: it stays alive, and About's animation must not tick unseen.
    let live: Bool
    let plugins: [PluginStatus]
    let actions: SettingsActions
    /// The app open on the side of Apps when the panel first draws (snapshots).
    let openApp: String?
    /// The plugin open on the side of Plugins when the panel first draws (snapshots).
    let openPlugin: String?
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var width: CGFloat = 900
    @Environment(\.theme) private var theme
    @Environment(\.settingsNav) private var nav

    public init(tab: Binding<SettingsTab>, config: GzymsConfig, problems: [String], broken: Bool, apps: [SeenApp],
                devices: [String], workspaceNames: [Int: String] = [:], grants: [GrantState] = [], calendars: [CalendarInfo] = [],
                logo: NSImage? = nil, live: Bool = true, plugins: [PluginStatus] = [], openApp: String? = nil, openPlugin: String? = nil, actions: SettingsActions) {
        self.logo = logo; self.live = live; self.plugins = plugins; self.openApp = openApp; self.openPlugin = openPlugin
        _tab = tab; self.config = config; self.problems = problems; self.broken = broken
        self.apps = apps; self.devices = devices; self.workspaceNames = workspaceNames; self.grants = grants
        self.calendars = calendars; self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) { header }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0; actions.height($0 + contentHeight) }
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .environment(\.settingsColumns, columns)
                    .buttonStyle(SlotButtonStyle())
                    .frame(maxWidth: CGFloat(columns) * 560)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .disabled(broken)
                    .opacity(broken ? 0.5 : 1)
                    .padding(.bottom, 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0; actions.height(headerHeight + $0) }
            }
            // The keyboard's setting stays in view on a tab longer than the panel.
            .onChange(of: nav?.current) { _, id in if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } } }
            }
        }
        .foregroundStyle(theme[\.text])
        .font(.system(size: 13))
        .frame(maxWidth: .infinity)
        .background(theme[\.base])
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func tabs(size: CGFloat, pad: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                Text(t.title)
                    .font(.system(size: size, weight: t == tab ? .semibold : .regular))
                    .foregroundStyle(t == tab ? theme[\.base] : theme[\.text])
                    .fixedSize()
                    .padding(.horizontal, pad).padding(.vertical, 5)
                    .background(Capsule().fill(t == tab ? theme[\.mauve] : theme[\.surface].opacity(0.0001)))
                    .contentShape(Capsule())
                    .onTapGesture { tab = t }
            }
        }
        .padding(.horizontal, 40)  // clear of the close button
    }

    /// Wide screens get sections side by side (Greg): one column per ~540 pt, up to three.
    private var columns: Int { max(1, min(3, Int((width - 48) / 540))) }

    @ViewBuilder private var header: some View {
            // A narrow panel gets tighter tabs before any is cut off.
            ViewThatFits(in: .horizontal) {
                tabs(size: 13, pad: 8)
                tabs(size: 12, pad: 5)
                tabs(size: 11, pad: 3)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme[\.overlay])
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: actions.close)
                    .padding(.trailing, 16)
                    .help("Close (Esc)")
            }
            .padding(.vertical, 10)
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if broken { Text("Fix config.toml first. Nothing is saved until it reads again.").bold() }
                    ForEach(problems, id: \.self) { Text($0) }
                }
                .font(.system(size: 12))
                .foregroundStyle(theme[\.base])
                .frame(maxWidth: CGFloat(columns) * 560, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme[\.peach]))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general: GeneralTab(config: config, names: workspaceNames, login: actions.loginItem(), write: actions.write,
                                  reveal: actions.revealConfig, openLoginItems: actions.openLoginItems)
        case .appearance: AppearanceTab(config: config, devices: devices, write: actions.write, openThemes: { tab = .themes })
        case .animations: AnimationsTab(config: config, write: actions.write)
        case .themes: ThemesTab(config: config, write: actions.write)
        case .notifications: NotificationsTab(config: config, actions: actions)
        case .apps: AppsTab(config: config, apps: apps, plugins: plugins, actions: actions, live: live, selected: openApp)
        case .modules: ModulesTab(config: config, write: actions.write, plugins: plugins)
        case .plugins: PluginsTab(config: config, write: actions.write, plugins: plugins, actions: actions, selected: openPlugin)
        case .calendar: CalendarTab(config: config, calendars: calendars, write: actions.write)
        case .agents: AgentsTab(config: config, write: actions.write, plugins: plugins, actions: actions, open: openPlugin == agentsFolder)
        case .sounds: SoundsTab(config: config, write: actions.write, actions: actions)
        case .shortcuts: ShortcutsTab(config: config, write: actions.write, recording: actions.recording)
        case .permissions: Section(title: "Permissions") {
            PermissionsView(states: grants, open: actions.openGrant, restart: actions.restart)
            if actions.hacks().noBanners {
                Row(title: "No banners", note: HacksTab.noBannersText) { Button("Restart") { actions.restartNotificationCenter() } }
            }
        }
        case .hacks: HacksTab(config: config, grants: grants, actions: actions, live: live)
        case .debug: DebugTab(config: config, apps: apps, actions: actions, live: live)
        case .about: AboutTab(version: actions.version, open: actions.openURL, canUpdate: actions.canCheckForUpdates,
                              checkUpdates: actions.checkForUpdates, homebrew: actions.homebrew, newVersion: actions.newVersion(), quit: actions.quit, config: config, logo: logo,
                              choose: actions.chooseLogo, write: actions.write, live: live)
        }
    }
}

// MARK: - Building blocks

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[\.overlay])
                .padding(.top, 14).padding(.bottom, 4)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 8).fill(theme[\.surface].opacity(0.6)))
        }
    }
}

extension EnvironmentValues {
    @Entry var settingsColumns = 1
}

/// A tab's sections, split in order into as many columns as the width allows.
private struct Columns<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsColumns) private var n

    var body: some View {
        Group(subviews: content) { subs in
            let per = max(1, Int((Double(subs.count) / Double(n)).rounded(.up)))
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(stride(from: 0, to: subs.count, by: per)), id: \.self) { start in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(subs[start..<min(subs.count, start + per)]) { $0 }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }
}

private struct Row<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let control: Control
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(theme[\.overlay]).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}

private struct Switch: View {
    let on: Bool
    let set: @MainActor (Bool) -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        Toggle("", isOn: Binding(get: { on }, set: set)).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(theme[\.mauve])
            .settingsSlot { set(!on) }
    }
}

@MainActor private func menu<T: Hashable>(_ value: T, _ options: [(T, String)], width: CGFloat = 150, set: @escaping (T) -> Void) -> some View {
    Picker("", selection: Binding(get: { value }, set: set)) {
        ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
    }
    .labelsHidden().pickerStyle(.menu).frame(width: width)
    .settingsSlot {
        guard !options.isEmpty else { return }
        let i = options.firstIndex { $0.0 == value } ?? -1
        set(options[(i + 1) % options.count].0)
    }
}

// MARK: - General

private struct GeneralTab: View {
    let config: GzymsConfig
    let names: [Int: String]
    let login: LoginItemStatus?
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let reveal: () -> Void
    let openLoginItems: () -> Void

    var body: some View {
        Columns {
        Section(title: "Login") {
            if login == nil {
                Row(title: "Start at login", note: "This dev build starts with launchd (install-dev.sh).") { EmptyView() }
            } else if login == .requiresApproval && config.startAtLogin {
                Row(title: "Start at login", note: "Turned off in System Settings. Turn it back on in Login Items.") {
                    Button("Login Items…", action: openLoginItems)
                }
            } else {
                Row(title: "Start at login", note: login == .notFound ? "macOS cannot find Gzyms. Move it to Applications." : nil) {
                    Switch(on: config.startAtLogin) { write("start_at_login", $0 ? nil : .bool(false), .table(["bar"])) }
                }
            }
        }
        Section(title: "Workspaces") {
            Row(title: "Show empty workspaces") { Switch(on: config.showEmpty) { write("show_empty", .bool($0), .table(["workspaces"])) } }
            Row(title: "Small bar on the notch screen", note: "when monitors are attached") {
                Switch(on: config.smallOnNotch) { write("small_on_notch", .bool($0), .table(["workspaces"])) }
            }
            if names.isEmpty {
                Row(title: "No tiling window manager running", note: "Gzyms reads workspaces from HyprMac. Colours below apply once it runs.") { EmptyView() }
            }
            ForEach(config.workspaces, id: \.number) { ws in WorkspaceRow(style: ws, name: names[ws.number], write: write) }
        }
        Section(title: "Caffeine") {
            Row(title: "Keep the display on too", note: "otherwise only the Mac stays awake, the screen may dim") {
                Switch(on: config.caffeineDisplay) { write("display", $0 ? .bool(true) : nil, .table(["caffeine"])) }
            }
            Row(title: "Stop on battery under", note: "lets the Mac sleep again before the battery runs out") {
                menu(config.caffeineBatteryBelow, [(0, "never"), (10, "10%"), (20, "20%"), (30, "30%"), (50, "50%")], width: 110) {
                    write("battery_below", $0 == 0 ? nil : .int($0), .table(["caffeine"]))
                }
            }
        }
        Section(title: "Config") {
            Row(title: "config.toml", note: "Every change here lands in this file. Edit it by hand any time.") {
                Button("Show in Finder", action: reveal)
            }
        }
        }
    }
}

private struct WorkspaceRow: View {
    let style: WorkspaceStyle
    let name: String?
    let write: (String, TOMLValue?, ConfigTable) -> Void
    @Environment(\.theme) private var theme
    private static let tokens = ["green", "peach", "pink", "sky", "mauve", "lavender", "gold", "red", "overlay", "text"]

    var body: some View {
        let row = ConfigTable.row("workspaces.style", key: "number", value: .int(style.number))
        HStack(spacing: 10) {
            Text("\(style.number)").bold().foregroundStyle(theme.color(style.color)).frame(width: 20)
            Text(name ?? "").foregroundStyle(theme[\.text])
            Spacer()
            ColorPicker("", selection: Binding(get: { theme.color(style.color) }, set: { c in
                if let hex = hex(c) { write("color", .string(hex), row) }
            }), supportsOpacity: false).labelsHidden()
            // A theme colour follows the theme. A colour from the picker stays put: the menu then says so,
            // and picking a theme colour goes back to one (Greg found "custom" doing nothing as a choice).
            let own = !Self.tokens.contains(style.color)
            menu(own ? "own" : style.color, (own ? [("own", "own colour")] : []) + Self.tokens.map { ($0, $0) }, width: 120) { t in
                if t != "own" { write("color", .string(t), row) }
            }
            .help(own ? "Set with the picker, so it stays the same in every theme" : "Follows the theme")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func hex(_ c: Color) -> String? {
        guard let s = NSColor(c).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255))
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    let config: GzymsConfig
    let devices: [String]
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let openThemes: () -> Void

    var body: some View {
        Columns {
        Section(title: "Look") {
            Row(title: "Theme", note: config.theme.name) { Button("Choose…", action: openThemes) }
            Row(title: "CPU chart") {
                menu(config.cpuChart.rawValue, [("line", "Line"), ("bars", "Bars")]) { write("chart", .string($0), .table(["cpu"])) }
            }
        }
        // Banned lives in `[audio] banned`, not in the icons: the bar popups and M and S leave it out.
        Section(title: "Device icons") {
            let banned = config.bannedDevices
            let names = devices + banned.subtracting(devices).sorted()  // a banned one unplugged now can still be let back in
            if names.isEmpty { Row(title: "No audio devices found") { EmptyView() } }
            ForEach(names, id: \.self) { d in
                Row(title: d, note: banned.contains(d) ? (d.localizedCaseInsensitiveContains("iphone") ? "banned, its camera too" : "banned") : nil) {
                    menu(banned.contains(d) ? "banned" : config.deviceIcons[d]?.rawValue ?? "auto",
                         [("auto", "Automatic")] + AudioDevice.Kind.allCases.map { ($0.rawValue, $0.rawValue.capitalized) } + [("banned", "Banned")]) { k in
                        let next = k == "banned" ? banned.union([d]) : banned.subtracting([d])
                        if next != banned { write("banned", next.isEmpty ? nil : .strings(next.sorted()), .table(["audio"])) }
                        write(d, k == "auto" || k == "banned" ? nil : .string(k), .table(["audio", "icons"]))
                    }
                }
            }
        }
        }
    }
}

// MARK: - Animations

private struct AnimationsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void

    private var entryNote: String {
        switch config.bannerEntry {
        case .icon: "The icon drops in, then the text unrolls out of it."
        case .drop: "Slides down from under the edge with a spring."
        case .notch: "Grows out of the notch."
        case .unroll: "Unrolls down from the top edge."
        case .pop: "Grows a little and fades in."
        case .fade: "Fades in where it stands."
        }
    }

    var body: some View {
        let table = ConfigTable.table(["appearance"])
        Columns {
        Section(title: "Motion") {
            Row(title: "Animations", note: "banner unroll, icon flight, count bump") {
                Switch(on: config.animations) { write("animations", .bool($0), table) }
            }
            Row(title: "Follow macOS Reduce motion", note: "with Reduce motion on, banners only fade") {
                Switch(on: config.followReduceMotion) { write("follow_reduce_motion", .bool($0), table) }
            }
        }
        Section(title: "Banner") {
            Row(title: "Entry", note: entryNote) {
                menu(config.bannerEntry, BannerEntry.allCases.map { ($0, $0 == .icon ? "Icon first" : $0.rawValue.capitalized) }, width: 110) {
                    write("banner_entry", $0 == .drop ? nil : .string($0.rawValue), table)
                }
            }
            Row(title: "Speed") {
                menu(config.animationSpeed, AnimationSpeed.allCases.map { ($0, $0.rawValue.capitalized) }, width: 110) {
                    write("animation_speed", $0 == .normal ? nil : .string($0.rawValue), table)
                }
            }
        }
        }
    }
}

// MARK: - Themes

/// Every theme as a small card in its own colours. A click puts it on, the star keeps it at the top (`favorite_themes`).
private struct ThemesTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    @State private var query = ""
    @State private var shade = "all"
    @Environment(\.theme) private var theme
    @Environment(\.settingsColumns) private var columns

    private var shown: [Theme] {
        let favorites = config.favoriteThemes
        let match = Theme.all.filter { t in
            (query.isEmpty || t.name.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "_")))
                && (shade == "all" || (shade == "favorites" ? favorites.contains(t.name) : (shade == "dark") == t.isDark))
        }
        return match.filter { favorites.contains($0.name) } + match.filter { !favorites.contains($0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("Search, e.g. tokyo", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
                Picker("", selection: $shade) {
                    Text("All").tag("all"); Text("Dark").tag("dark"); Text("Light").tag("light"); Text("★ Favourites").tag("favorites")
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 320)
                Spacer()
                Text("\(shown.count) of \(Theme.all.count). Every one keeps text and colours readable.")
                    .font(.system(size: 11)).foregroundStyle(theme[\.overlay])
            }
            .padding(.top, 14)
            // Plain rows, not a lazy grid: the panel takes its height from the content, and a lazy grid guesses it.
            let perRow = columns * 2, list = shown
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 0, to: list.count, by: perRow)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(list[start..<min(list.count, start + perRow)], id: \.name) { t in
                            ThemeCard(t: t, on: t.name == config.theme.name, favorite: config.favoriteThemes.contains(t.name)) {
                                write("theme", .string(t.name), .table([]))
                            } star: { star(t.name) }
                        }
                        // A short last row keeps the card width of the full ones.
                        ForEach(0..<(perRow - min(perRow, list.count - start)), id: \.self) { _ in Color.clear.frame(height: 1) }
                    }
                }
            }
        }
    }

    private func star(_ name: String) {
        var f = config.favoriteThemes
        if let i = f.firstIndex(of: name) { f.remove(at: i) } else { f.append(name) }
        write("favorite_themes", f.isEmpty ? nil : .strings(f), .table(["appearance"]))
    }
}

/// One theme drawn in itself: its background, its name in its text colour, its six accents.
private struct ThemeCard: View {
    let t: Theme
    let on: Bool
    let favorite: Bool
    let pick: () -> Void
    let star: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(t.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(t[\.text]).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach([\Theme.red, \.peach, \.gold, \.green, \.sky, \.mauve], id: \.self) { k in
                        Circle().fill(t[k]).frame(width: 10, height: 10)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: favorite ? "star.fill" : "star")
                .foregroundStyle(favorite ? t[\.gold] : t[\.overlay])
                .contentShape(Rectangle())
                .onTapGesture(perform: star)
                .help(favorite ? "Take it off your favourites" : "Keep it at the top")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(t[\.base]))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? theme[\.mauve] : t[\.surface], lineWidth: on ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .settingsSlot(choose: pick)
    }
}

// MARK: - Plugins

/// The bar's layout and its built-in parts, each of which can be turned off (spec: "everything on the bar is a plugin").
/// Off = gone and not sampled. Plugins sit in the layout too, their own settings are on the Plugins tab.
private struct ModulesTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let plugins: [PluginStatus]
    @Environment(\.theme) private var theme

    private var layout: BarLayoutPlan { barLayout(left: config.layoutLeft, right: config.layoutRight, plugins: plugins.map(\.folder)) }
    private var recommended: BarLayoutPlan { .recommended(plugins: plugins.map(\.folder)) }

    /// The recommended layout is no keys at all, so a later default (a new widget, a new plugin) reaches the user too.
    private func writeLayout(_ p: BarLayoutPlan) {
        let same = p == recommended
        write("left", same ? nil : .strings(p.left.map(\.name)), .table(["widgets"]))
        write("order", same ? nil : .strings(p.right.map(\.name)), .table(["widgets"]))
    }

    /// `moved` lands before `target` on target's side, or at the end of `side` when dropped on its header.
    private func move(_ name: String, before target: BarSlot?, side: KeyPath<BarLayoutPlan, [BarSlot]>) {
        guard let moved = BarSlot(name), moved != target else { return }
        var p = layout
        p.left.removeAll { $0 == moved }
        p.right.removeAll { $0 == moved }
        let toLeft = side == \BarLayoutPlan.left
        var list = toLeft ? p.left : p.right
        list.insert(moved, at: target.flatMap { list.firstIndex(of: $0) } ?? list.endIndex)
        if toLeft { p.left = list } else { p.right = list }
        writeLayout(p)
    }

    private func title(_ s: BarSlot) -> String {
        switch s {
        case .widget(let w): w.title
        case .plugin(let f): plugins.first { $0.folder == f }?.name ?? f
        }
    }

    @ViewBuilder private func side(_ name: String, _ note: String, _ kp: KeyPath<BarLayoutPlan, [BarSlot]>) -> some View {
        Row(title: name, note: note) { EmptyView() }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { names, _ in names.first.map { move($0, before: nil, side: kp) }; return true }
        ForEach(layout[keyPath: kp], id: \.self) { s in
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal").foregroundStyle(theme[\.overlay]).padding(.leading, 12)
                Row(title: title(s), note: { if case .plugin = s { "your plugin" } else { nil } }()) {
                    if case .widget(let w) = s {
                        Switch(on: !config.hiddenWidgets.contains(w)) { write(w.rawValue, $0 ? nil : .bool(false), .table(["widgets"])) }
                    }
                }
            }
            .contentShape(Rectangle())
            .draggable(s.name)
            .dropDestination(for: String.self) { names, _ in names.first.map { move($0, before: s, side: kp) }; return true }
        }
    }

    var body: some View {
        Columns {
            Section(title: "Bar layout · drag between the sides and within them") {
                side("Left of the notch", "after the workspaces", \.left)
                side("Right of the notch", "up to the clock", \.right)
                if layout != recommended {
                    Row(title: "Layout", note: "plugins left, built-ins right") { Button("Reset layout") { writeLayout(recommended) } }
                }
            }
        }
    }
}

/// Plugins as a list, one line each: icon, name, what it does, how it is, a switch. A click opens one on the side
/// with its options, as in Apps (Greg, 2026-11-05: the form per plugin was too much at once).
private struct PluginsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let plugins: [PluginStatus]
    let actions: SettingsActions
    @State var selected: String?
    @State private var adding = false
    @State private var dropping = false
    @State private var dropProblem: String?
    @Environment(\.theme) private var theme
    @Environment(\.settingsNav) private var nav

    /// Agents have their own tab, so the list and the catalog leave it out.
    private var listed: [PluginStatus] { plugins.filter { $0.folder != agentsFolder } }
    private var addable: [CatalogPlugin] { pluginCatalog.filter { c in c.name != agentsFolder && !plugins.contains { $0.folder == c.name } } }

    var body: some View {
        Columns {
            Section(title: "Plugins") {
                ForEach(listed, id: \.folder) { p in
                    PluginRow(p: p, selected: selected == p.folder, write: write) { selected = selected == p.folder ? nil : p.folder }
                }
                Button { adding.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: adding ? "chevron.down" : "chevron.right").font(.system(size: 9)).frame(width: 12)
                        Text("Add a plugin")
                    }
                }
                .buttonStyle(.borderless).foregroundStyle(theme[\.overlay])
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
                if adding { add }
            }
            if let p = listed.first(where: { $0.folder == selected }) {
                Section(title: p.name) {
                    PluginDrawer(p: p, config: config, write: write, actions: actions, close: { selected = nil })
                }
            }
        }
        // Esc closes the drawer first, the panel on the next press.
        .onChange(of: selected) { _, s in nav?.escape = s == nil ? nil : { selected = nil } }
        .onDisappear { nav?.escape = nil }
    }

    /// The catalog's ready plugins, a folder to drop, and the warning that goes with installing one.
    @ViewBuilder private var add: some View {
        ForEach(addable, id: \.name) { c in
            Row(title: c.name, note: c.summary) { Button("Add") { actions.addPlugin(c.name) } }
        }
        HStack {
            Text(dropProblem ?? "Drop a plugin folder here (with its plugin.toml)")
                .foregroundStyle(dropProblem == nil ? theme[\.overlay] : theme[\.red])
            Text("or")
            Button("Choose folder…", action: actions.choosePlugin)
        }
        .frame(maxWidth: .infinity).padding(14)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(dropping ? theme[\.mauve] : theme[\.overlay].opacity(0.5),
                                                                   style: StrokeStyle(lineWidth: 1, dash: [4])))
        .padding(10)
        .dropDestination(for: URL.self) { urls, _ in
            dropProblem = urls.compactMap(actions.installPlugin).first
            return true
        } isTargeted: { dropping = $0 }
        Row(title: "Make your own", note: "gzyms plugin new <name> makes a working one. Edited a plugin? Turn it off and on. Teach your coding agent: gzyms skill install") { EmptyView() }
        // Plugins are child processes of Gzyms, so macOS lets them do what Gzyms may (spec: say so where you install).
        Text("Plugins run with Gzyms' permissions: Full Disk Access, Accessibility, camera and microphone if granted. Install only what you trust.")
            .font(.system(size: 11)).foregroundStyle(theme[\.peach])
            .padding(.horizontal, 12).padding(.vertical, 7)
    }
}

/// One line of a plugin list: icon, name, what it does, how it is, a switch. Plugins and Agents draw it the same way.
private struct PluginRow: View {
    let p: PluginStatus
    var name: String?
    let selected: Bool
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let pick: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let (state, color) = state
        let symbol = p.icon.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 } ?? "puzzlepiece.extension"
        return HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(theme[\.overlay]).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? p.name).lineLimit(1)
                if let line = p.description.components(separatedBy: ". ").first, !line.isEmpty {
                    Text(line).font(.system(size: 11)).foregroundStyle(theme[\.overlay]).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(state)
            }
            .font(.system(size: 12)).foregroundStyle(color == theme[\.green] ? theme[\.overlay] : color)
            .frame(width: 104, alignment: .leading)
            Switch(on: p.enabled) { write("enabled", $0 ? nil : .bool(false), .table(["plugins", p.folder])) }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? theme[\.surface] : .clear).padding(.horizontal, 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .settingsSlot(choose: pick)
        .help(p.problem ?? "")
    }

    private var state: (String, Color) {
        if p.problem != nil { return ("Error", theme[\.red]) }
        if p.catalogNewer { return ("You changed it", theme[\.peach]) }
        if !p.enabled { return ("Off", theme[\.overlay]) }
        return p.running ? ("Running", theme[\.green]) : ("Starting", theme[\.overlay])
    }
}

/// One plugin on the side of Settings → Plugins: what it does, what is wrong, its update, its options, remove.
private struct PluginDrawer: View {
    let p: PluginStatus
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let actions: SettingsActions
    let close: () -> Void
    /// Agents are built in: the switch turns them off, there is nothing to remove.
    var removable = true
    @Environment(\.theme) private var theme

    var body: some View {
        if let problem = p.problem {
            Text(problem).font(.system(size: 12)).foregroundStyle(theme[\.red]).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 7)
        }
        if !p.description.isEmpty {
            Text(p.description).font(.system(size: 12)).foregroundStyle(theme[\.overlay]).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 7)
        }
        if p.catalogNewer {
            Row(title: "You changed \(p.folder)", note: "Gzyms has a newer version. Update it from the catalog? Your copy is kept as \(p.folder).bak-<date>.") {
                Button("Update") { actions.updatePlugin(p.folder) }
            }
        }
        ForEach(p.options, id: \.key) { o in
            PluginOptionRow(option: o, value: config.pluginOptions[p.folder]?[o.key] ?? o.defaultValue) { v in
                write(o.key, v == o.defaultValue ? nil : v, .table(["plugins", p.folder]))
            }
        }
        if removable {
            HStack {
                Button("Remove") { close(); actions.removePlugin(p.folder) }
                Spacer()
                Button("Show in Finder") { actions.revealPlugin(p.folder) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

/// The catalog plugin that holds the agents for now. Settings → Agents shows it, Settings → Plugins does not.
private let agentsFolder = "agents"

/// Agents: the tuios integration as one row and its options on the side, drawn like Plugins. Not installed: Turn on.
private struct AgentsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let plugins: [PluginStatus]
    let actions: SettingsActions
    @State var open = false
    @Environment(\.theme) private var theme
    @Environment(\.settingsNav) private var nav

    var body: some View {
        let p = plugins.first { $0.folder == agentsFolder }
        Columns {
            Section(title: "Agents") {
                if let p {
                    PluginRow(p: p, name: "tuios", selected: open, write: write) { open.toggle() }
                } else if let c = pluginCatalog.first(where: { $0.name == agentsFolder }) {
                    Row(title: "tuios", note: c.summary.components(separatedBy: ". ").first ?? c.summary) {
                        Button("Turn on") { actions.addPlugin(c.name) }
                    }
                }
            }
            if let p, open {
                Section(title: "tuios") {
                    PluginDrawer(p: p, config: config, write: write, actions: actions, close: { open = false }, removable: false)
                }
            }
            Section(title: "Coming later") {
                Text("Other agent tools come later.")
                    .font(.system(size: 12)).foregroundStyle(theme[\.overlay])
                    .padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
        // Esc closes the drawer first, the panel on the next press.
        .onChange(of: open) { _, o in nav?.escape = o ? { open = false } : nil }
        .onDisappear { nav?.escape = nil }
    }
}

/// One option of a plugin, its control from the option's type. Text-like ones save on Return.
private struct PluginOptionRow: View {
    let option: PluginOption
    let value: TOMLValue?
    let set: (TOMLValue) -> Void

    private var text: String {
        switch value {
        case .strings(let a)?: a.joined(separator: ", ")
        case .ints(let a)?: a.map(String.init).joined(separator: ", ")
        case let v?: PluginOption.envText(v)
        case nil: ""
        }
    }

    var body: some View {
        Row(title: option.title, note: option.note ?? (option.kind == .list ? "comma separated, Return saves" : nil)) {
            switch option.kind {
            case .toggle: Switch(on: value == .bool(true)) { set(.bool($0)) }
            case .choice: menu(text, option.choices.map { ($0, $0) }, width: 160) { set(.string($0)) }
            case .text, .number, .list: CommitField(text: text, commit: save).frame(width: 220)
            }
        }
    }

    private func save(_ draft: String) {
        guard draft != text else { return }
        switch option.kind {
        case .number:
            if let i = Int(draft) { set(.int(i)) } else if let d = Double(draft.replacingOccurrences(of: ",", with: ".")) { set(.double(d)) }
        case .list: set(.strings(draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        default: set(.string(draft))
        }
    }
}

/// A text field that saves on Return, Tab or a click elsewhere. SwiftUI's `onSubmit` never fired in the settings
/// panel (it is never the active app's window), so not one plugin option was ever saved (Greg, 2026-10-31).
private struct CommitField: NSViewRepresentable {
    let text: String
    /// Dots instead of the value: keys and tokens.
    var secure = false
    let commit: (String) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = secure ? NSSecureTextField(string: text) : NSTextField(string: text)
        f.bezelStyle = .roundedBezel
        f.lineBreakMode = .byTruncatingHead  // a long path shows its file name
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.commit = commit
        if f.currentEditor() == nil, f.stringValue != text { f.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(commit: commit) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var commit: (String) -> Void
        init(commit: @escaping (String) -> Void) { self.commit = commit }
        func controlTextDidEndEditing(_ n: Notification) {
            if let f = n.object as? NSTextField { commit(f.stringValue) }
        }
    }
}

// MARK: - Calendar

private struct CalendarTab: View {
    let config: GzymsConfig
    let calendars: [CalendarInfo]
    let write: (String, TOMLValue?, ConfigTable) -> Void
    private static let points: [(Int, String)] = [(5, "5 min before"), (3, "3 min before"), (0, "At the start"), (-3, "3 min after")]

    var body: some View {
        Columns {
            Section(title: "Meetings") {
                Row(title: "Meeting reminders", note: "for meetings with a video link") {
                    Switch(on: config.calendarEnabled) { write("enabled", $0 ? nil : .bool(false), .table(["calendar"])) }
                }
                Row(title: "Remind me", note: remindNote) {
                    menu(config.meetingPoints.first ?? 3, Self.points, width: 150) {
                        write("points", $0 == 3 ? nil : .ints([$0]), .table(["calendar"]))
                    }
                }
                Row(title: "Check before joining", note: "camera, microphone and speakers first, then Join. Off opens the link at once.") {
                    Switch(on: config.meetingPreview) { write("preview", $0 ? nil : .bool(false), .table(["calendar"])) }
                }
            }
            Section(title: "Calendars") {
                if calendars.isEmpty {
                    Row(title: "No calendars yet", note: "Turn the reminders on and allow calendar access in Permissions.") { EmptyView() }
                }
                ForEach(calendars.sorted { ($0.account, $0.title) < ($1.account, $1.title) }, id: \.key) { c in
                    Row(title: c.title, note: c.account) {
                        Switch(on: !config.calendarSkip.contains(c.key)) { on in
                            let next = on ? config.calendarSkip.subtracting([c.key]) : config.calendarSkip.union([c.key])
                            write("skip", next.isEmpty ? nil : .strings(next.sorted()), .table(["calendar"]))
                        }
                    }
                }
            }
        }
    }

    private var remindNote: String {
        switch config.meetingPoints.first ?? 3 {
        case 5: "early, time to finish a thought"
        case 3: "time to check the camera"
        case 0: "for people who like risk"
        default: "the team is late anyway"
        }
    }
}

// MARK: - Shortcuts, Sounds, About

private struct ShortcutsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let recording: (Bool) -> Void
    var body: some View {
        Columns {
            Section(title: "Keyboard mode") {
                LeaderRow(leader: config.leader, recording: recording) { write("leader", .string($0), .table(["keys"])) }
                LetterRow(title: "Open", key: "open", letter: config.verbs.open, config: config, write: write)
                LetterRow(title: "Dismiss", key: "dismiss", letter: config.verbs.dismiss, config: config, write: write)
                LetterRow(title: "Snooze", key: "snooze", letter: config.verbs.snooze, config: config, write: write)
                LetterRow(title: "Second action", key: "alt", letter: config.verbs.alt, config: config, write: write)
                LetterRow(title: "Next waiting banner", key: "next", letter: config.verbs.next, config: config, write: write)
                LetterRow(title: "Previous waiting banner", key: "prev", letter: config.verbs.prev, config: config, write: write)
                LetterRow(title: "Clear a list (press twice)", key: "clear", letter: config.verbs.clear, config: config, write: write)
            }
            Section(title: "Global") {
                ShortcutRow(title: "Mute or unmute the microphone", shortcut: config.micShortcut, recording: recording) {
                    write("mic_mute", .string($0?.text ?? "off"), .table(["shortcuts"]))
                }
            }
            Section(title: "macOS menu bar") {
                Row(title: "Show it while you hold", note: "with the pointer on the bar. The bar slides away until the pointer leaves the top.") {
                    menu(config.menuBarKey.rawValue, MenuBarKey.allCases.map { ($0.rawValue, $0.name) }) {
                        write("menu_bar_key", $0 == "cmd" ? nil : .string($0), .table(["bar"]))
                    }
                }
            }
        }
    }
}

/// Click the cap, press the leader: an F key, a letter or digit with ⌃ ⌥ ⌘, or ⌃ ⌥ ⌘ alone. Esc cancels.
/// The keyboard tap stands aside meanwhile, else the leader would turn the mode on instead of being recorded.
private struct LeaderRow: View {
    let leader: Leader?
    let recording: (Bool) -> Void
    let set: (String) -> Void
    @State private var monitor: Any?
    /// The one modifier down so far with nothing else: let go of it and it is the leader.
    @State private var lone: String?
    @State private var warning: String?
    @Environment(\.theme) private var theme

    private var note: String {
        switch leader {
        case nil: "Off. gzyms keys on still turns the mode on."
        case .modifier?: "Tap it alone for the mode. Held, it takes only the banner's letters while a banner is up."
        case .key?: "Tap it for the mode, or hold it and press a letter. Letters show over the bar."
        case .chord?: "Press it for the mode. Letters show over the bar."
        }
    }

    var body: some View {
        Row(title: "Leader", note: warning ?? note) {
            HStack(spacing: 8) {
                Text(monitor != nil ? "press a key" : leader?.symbol ?? "Off")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(monitor != nil ? theme[\.mauve].opacity(0.4) : theme[\.surface]))
                    .onTapGesture(perform: record)
                    .settingsSlot(choose: record)
                if leader != nil { Button("Off") { set("off") } }
            }
        }
        .onDisappear(perform: stop)
    }

    private func record() {
        guard monitor == nil else { return }
        warning = nil
        recording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if e.type == .flagsChanged {
                let f = e.modifierFlags.intersection([.control, .option, .command, .shift])
                let one: [(NSEvent.ModifierFlags, String)] = [(.control, "ctrl"), (.option, "alt"), (.command, "cmd")]
                if f.isEmpty, let m = lone { done(m) } else { lone = one.first { $0.0 == f }?.1 }
                return e
            }
            lone = nil
            if e.keyCode == 53 { stop(); return nil }  // Esc
            if let f = Leader.fKeys.first(where: { $0.value == Int64(e.keyCode) })?.key { done(f); return nil }
            let f = e.modifierFlags
            if let key = Shortcut.key(forCode: Int64(e.keyCode)) {
                let s = Shortcut(ctrl: f.contains(.control), alt: f.contains(.option), cmd: f.contains(.command), shift: f.contains(.shift), key: key)
                if s.ctrl || s.alt || s.cmd { done(s.text); return nil }
            }
            warning = "Use an F key, a letter or digit with ⌃ ⌥ ⌘, or ⌃ ⌥ ⌘ alone"
            stop()
            return nil
        }
    }

    private func done(_ text: String) { stop(); set(text) }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); recording(false) }
        monitor = nil; lone = nil
    }
}

/// Click the cap, press the combination. Esc cancels, Off turns it off.
private struct ShortcutRow: View {
    let title: String
    let shortcut: Shortcut?
    let recording: (Bool) -> Void
    let set: (Shortcut?) -> Void
    @State private var monitor: Any?
    @State private var warning: String?
    @Environment(\.theme) private var theme

    var body: some View {
        Row(title: title, note: warning ?? (shortcut?.clashesWithHyprMac == true ? "HyprMac uses Ctrl chords. Add ⌥ or ⌘." : "Works in every app.")) {
            HStack(spacing: 8) {
                Text(monitor != nil ? "press keys" : shortcut?.symbol ?? "Off")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(monitor != nil ? theme[\.mauve].opacity(0.4) : theme[\.surface]))
                    .onTapGesture(perform: record)
                    .settingsSlot(choose: record)
                if shortcut != nil { Button("Off") { set(nil) } }
            }
        }
        .onDisappear(perform: stop)
    }

    private func record() {
        guard monitor == nil else { return }
        warning = nil
        recording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            defer { stop() }
            if e.keyCode == 53 { return nil }  // Esc
            let f = e.modifierFlags
            guard let key = Shortcut.key(forCode: Int64(e.keyCode)) else { warning = "Use a letter or a digit"; return nil }
            let s = Shortcut(ctrl: f.contains(.control), alt: f.contains(.option), cmd: f.contains(.command), shift: f.contains(.shift), key: key)
            guard s.ctrl || s.alt || s.cmd else { warning = "Hold ⌃, ⌥ or ⌘ with the key"; return nil }
            set(s)
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); recording(false) }
        monitor = nil
    }
}

private struct SoundsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let actions: SettingsActions
    var body: some View {
        Section(title: "Sounds") {
            Row(title: "Sounds") {
                Switch(on: config.notificationSounds) { write("sounds", .bool($0), .table(["notifications"])) }
            }
            ForEach(SoundEvent.allCases, id: \.self) { e in SoundRow(event: e, choice: config.sounds[e], write: write, actions: actions) }
        }
    }
}

/// One event: Gzyms' tone, a macOS sound or a file of your own, and ▶ to hear it.
private struct SoundRow: View {
    let event: SoundEvent
    let choice: String?
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let actions: SettingsActions
    private static let own = "\u{1}own"
    private static let when: [SoundEvent: String] = [
        .message: "Notifications from apps, and anything without a sound of its own",
        .success: "An agent is done",
        .fail: "Errors and critical ones",
        .waiting: "An agent waits for you",
        .armageddon: "The full-screen alarm, every 1.5 s until clicked",
        .dismiss: "A banner is dismissed: a swipe, a key or the wheel",
    ]

    private var current: String { choice ?? event.defaultChoice }
    private var isFile: Bool { if case .file = SoundSource(current, event: event) { true } else { false } }

    private var options: [(String, String)] {
        [(SoundSource.cat, "Gzyms cat"), (SoundSource.gzyms, "Gzyms tone")] + macSounds.map { ($0, "macOS \($0)") }
            + (isFile ? [(current, (current as NSString).lastPathComponent)] : []) + [(Self.own, "Own file…")]
    }

    var body: some View {
        Row(title: event.rawValue, note: Self.when[event]) {
            HStack(spacing: 8) {
                menu(current, options, width: 170) { v in
                    if v == Self.own { actions.chooseSound(event); return }
                    write(event.rawValue, v == event.defaultChoice ? nil : .string(v), .table(["sounds"]))
                    actions.playSound(event)
                }
                Button { actions.playSound(event) } label: { Image(systemName: "play.fill") }
            }
        }
    }
}

private struct AboutTab: View {
    let version: String
    let open: (String) -> Void
    let canUpdate: Bool
    let checkUpdates: () -> Void
    let homebrew: Bool
    let newVersion: String?
    let quit: () -> Void
    let config: GzymsConfig
    let logo: NSImage?
    let choose: () -> Void
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let live: Bool
    @State private var landed = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            hero
            columns
        }
    }

    /// The cat drops onto its cornice when the tab opens, then lives a little: tail, blink, a glowing island.
    /// The clock runs only while About is on screen.
    private var hero: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { ctx in
                GzymsLogo(t: ctx.date.timeIntervalSinceReferenceDate).frame(width: 132, height: 124)
            }
            .offset(y: landed ? 0 : -60)
            .opacity(landed ? 1 : 0)
            .busy("settings: about cat, 30 fps", while: live)
            Text("gzyms").font(.system(size: 30, weight: .bold, design: .monospaced))
            Text("The cornice of your screen: workspaces, notifications and meetings, up where your eyes already are.")
                .font(.system(size: 13)).foregroundStyle(theme[\.overlay]).multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text("Version \(version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme[\.overlay])
                .opacity(landed ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 16)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { landed = true } }
        .onDisappear { landed = false }
    }

    private var logoNote: String {
        guard let path = config.logo else { return "The cat on the cornice. A unicorn works too: PNG, PDF or SVG." }
        return logo == nil ? "\((path as NSString).lastPathComponent) could not be read, the cat stays." : (path as NSString).lastPathComponent
    }

    private var columns: some View {
        Columns {
            Section(title: "Gzyms") {
                Row(title: "Version \(version)", note: canUpdate ? nil : "Updates come with the first release.") {
                    if canUpdate { Button("Check for Updates…", action: checkUpdates) }
                }
                if let newVersion {
                    Row(title: "Update to \(newVersion)", note: "Run brew upgrade gzyms in a terminal.") {
                        HStack(spacing: 8) {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew upgrade gzyms", forType: .string)
                            }
                            Button("Release") { open(releaseURL(version: newVersion)) }
                        }
                    }
                }
                if canUpdate {
                    let on = automaticUpdates(chosen: config.updatesAutomatic, homebrew: homebrew)
                    Row(title: "Automatic updates", note: homebrew ? "Installed with Homebrew. Update with brew upgrade gzyms." : nil) {
                        // Written only when it differs from the default, like every other setting.
                        Switch(on: on) { write("automatic", $0 == !homebrew ? nil : .bool($0), .table(["updates"])) }
                    }
                    if homebrew && on {
                        Text("Sparkle and brew can both update Gzyms. That can break an update.")
                            .font(.system(size: 11)).foregroundStyle(theme[\.peach]).padding(.horizontal, 12).padding(.bottom, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Row(title: "Tutorial", note: "The keys in 5 minutes.") { Button("Learn Gzyms…") { open(tutorialURL.absoluteString) } }
                Row(title: "Website") { Button("gzyms.dev") { open("https://gzyms.dev") } }
                Row(title: "Source") { Button("GitHub") { open("https://github.com/zalewskigrzegorz/gzyms") } }
                Row(title: "Changes") { Button("Changelog") { open("https://github.com/zalewskigrzegorz/gzyms/commits/main") } }
                Row(title: "Quit", note: "Shortcut: ⌘Q while Settings is in front.") { Button("Quit Gzyms", action: quit) }
            }
            Section(title: "Your logo") {
                Row(title: "Logo on the bar", note: logoNote) {
                    HStack(spacing: 8) {
                        Group {
                            if let logo { Image(nsImage: logo).resizable().scaledToFit() } else { GzymsLogo() }
                        }
                        .frame(width: 26, height: 24)
                        Button("Choose…", action: choose)
                        if config.logo != nil { Button("Back to the cat") { write("logo", nil, .table(["bar"])) } }
                    }
                }
            }
            Section(title: "License") {
                Row(title: "Gzyms", note: "Grzegorz Zalewski, MIT") { Button("License") { open("https://github.com/zalewskigrzegorz/gzyms/blob/main/LICENSE") } }
                // Listed by hand: NotificationNanny is adapted code, not a package in Package.resolved.
                Row(title: "TOMLDecoder", note: "Daniel Duan, MIT") { Button("Source") { open("https://github.com/dduan/TOMLDecoder") } }
                Row(title: "Sparkle", note: "Sparkle Project, MIT") { Button("Source") { open("https://github.com/sparkle-project/Sparkle") } }
                Row(title: "NotificationNanny", note: "chessper53, MIT. Parts of reading and hiding banners.") {
                    Button("Source") { open("https://github.com/chessper53/NotificationNanny") }
                }
            }
        }
    }
}

// MARK: - Debug

private struct DebugTab: View {
    let config: GzymsConfig
    let apps: [SeenApp]
    let actions: SettingsActions
    let live: Bool
    @State private var reported: String?
    /// Bumped by Forget, so the list reads again at once.
    @State private var reread = 0
    @Environment(\.theme) private var theme
    @Environment(\.fixedNow) private var fixedNow

    private static let ago: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en")
        return f
    }()

    var body: some View {
        Columns {
            Section(title: "Watching") {
                Row(title: "Anomaly detector", note: "main-thread stalls, rebuild storms, stale data") {
                    Switch(on: config.anomalies) { actions.write("anomalies", $0 ? nil : .bool(false), .table(["debug"])) }
                }
                Row(title: "Usage HUD", note: "CPU, memory and lag of Gzyms itself") { Button("Show", action: actions.showHUD) }
                Row(title: "Event log") { Button("Open log", action: actions.openLog) }
            }
            Section(title: "Something wrong?") {
                Row(title: "Report a problem", note: reported ?? "One zip on the Desktop: log, anomalies, config and versions. No notification text, tokens or personal names.") {
                    Button("Make report…") {
                        reported = actions.report().map { "Saved as \($0.lastPathComponent) on the Desktop. Attach it to the GitHub discussion that opens." }
                            ?? "Could not make the report. The log says why."
                    }
                }
                Row(title: "Missing something?") { Button("Request a feature…", action: actions.requestFeature) }
            }
            TimelineView(.periodic(from: .now, by: live ? 2 : 3600)) { _ in
                let _ = reread
                duplicates(actions.duplicates())
            }
        }
    }

    private func app(_ id: String) -> SeenApp { apps.first { $0.id == id } ?? SeenApp(id: id, name: id, icon: nil) }

    private func duplicates(_ d: DuplicatesState) -> some View {
        Section(title: "Same notification, several apps") {
            Row(title: "Tell me about them", note: "One gzyms notification for each new pair of apps.") {
                Switch(on: d.warningsOn) { actions.setDuplicateWarnings($0); reread += 1 }
            }
            if d.groups.isEmpty {
                Row(title: "None seen", note: "Apps that send the same text at the same moment show up here.") {}
            }
            ForEach(d.groups.sorted { $0.last > $1.last }, id: \.apps) { g in
                Row(title: joinNames(g.apps.map { app($0).name }),
                    note: "\(g.count == 1 ? "Once" : "\(g.count) times"). Last \(Self.ago.localizedString(for: g.last, relativeTo: fixedNow ?? Date())).") {
                    Button("Forget") { actions.forgetDuplicates(g.apps); reread += 1 }
                }
                ForEach(g.apps, id: \.self) { id in
                    HStack(spacing: 10) {
                        Group { if let icon = app(id).icon { Image(nsImage: icon).resizable() } else { Color.clear } }.frame(width: 18, height: 18)
                        Text(app(id).name).lineLimit(1)
                        Spacer()
                        Button("Open in macOS") { actions.openAppNotifications(id) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Hacks

/// What Settings → Hacks reads from the Mac: each hack's live state.
public struct HacksState: Equatable {
    /// One Gecko profile and whether it left the media keys to the music player.
    public struct Profile: Equatable {
        public var browser: String, name: String
        public var keysOff: Bool
        public init(browser: String, name: String, keysOff: Bool) { self.browser = browser; self.name = name; self.keysOff = keysOff }
    }
    public var profiles: [Profile] = []
    public var musicAppRunning = false
    public var serverListening = false
    public var tabs = 0
    /// "native", "osascript", or "" when the music pill is off.
    public var reader = ""
    /// When usernoted last said an app sent something.
    public var lastSignal: Date?
    /// The Accessibility observer on Notification Center is attached.
    public var bannerAXOn = false
    /// When the last macOS banner was read.
    public var lastBanner: Date?
    /// NotificationNanny runs: two observers fight over one banner.
    public var nannyRunning = false
    /// Apps send notifications but Notification Center shows no banner (`BannerGuard`).
    public var noBanners = false
    /// Notification Center restarts by Gzyms since it started, the last one, and no banner has shown since it.
    public var ncRestarts = 0
    public var ncLastRestart: Date?
    public var ncStillHung = false
    public init() {}
}

/// Everything in Gzyms that rides on a private API or a trick, one tile each: what it does, what it rests on, what can
/// break it, its state right now, and one control (Greg, 2026-11-03).
private struct HacksTab: View {
    let config: GzymsConfig
    let grants: [GrantState]
    let actions: SettingsActions
    let live: Bool
    @Environment(\.theme) private var theme

    private static let docs = "https://gzyms.dev/docs/#hacks"
    private static let pref = "media.hardwaremediakeys.enabled"

    var body: some View {
        TimelineView(.periodic(from: .now, by: live ? 2 : 3600)) { _ in
            let h = actions.hacks()
            Columns {
                Section(title: "Media") {
                    Row(title: "Media keys for the music player only",
                        note: state(h.profiles.isEmpty ? "No Firefox-based browser found."
                                    : h.profiles.map { "\($0.browser) \($0.name): \($0.keysOff ? "off" : "on")" }.joined(separator: ". ") + ".",
                                    ok: !h.profiles.isEmpty && h.profiles.allSatisfy(\.keysOff))
                            + " The browser leaves the media keys to the music player.") {
                        Button("Copy pref") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.pref, forType: .string)
                        }
                    }
                    Row(title: "Browser tabs in the music pill",
                        note: state(!config.browserMedia ? "Off." : !h.serverListening ? "Port 47100 is busy. Quit Gzyms Probe." : "\(h.tabs) tab(s) report media.",
                                    ok: config.browserMedia && h.serverListening)
                            + " Tabs that play show in the music pill. Needs Tampermonkey and the script.") {
                        HStack(spacing: 8) {
                            Button("Open script") { actions.openURL("http://127.0.0.1:47100/gzyms-media.user.js") }.disabled(!h.serverListening)
                            Switch(on: config.browserMedia) { actions.write("browser_media", $0 ? .bool(true) : nil, .table(["hacks"])) }
                        }
                    }
                    Row(title: "Music.app off the media keys",
                        note: state(h.musicAppRunning ? "Music.app is running." : "Music.app is not running.", ok: !h.musicAppRunning)
                            + " A running Music.app takes the media keys. Quit it when you play from Spotify.") {
                        Button("Quit Music.app") { actions.quitApp("com.apple.Music") }.disabled(!h.musicAppRunning)
                    }
                    Row(title: "What plays",
                        note: state(h.reader == "native" ? "Native reader." : h.reader == "osascript" ? "Fallback reader. Now Playing only." : "Off. The music pill is hidden.",
                                    ok: h.reader == "native")
                            + " Reads what plays from macOS for the music pill.") {
                        docsButton
                    }
                }
                Section(title: "Notifications") {
                    Row(title: "Instant banners",
                        note: state(bannersState(h), ok: config.bannerAX && h.bannerAXOn && !h.nannyRunning && !h.noBanners)
                            + " The banner text shows at once, not a few seconds later.") {
                        Switch(on: config.bannerAX) { actions.write("banner_ax", $0 ? nil : .bool(false), .table(["notifications"])) }
                    }
                    Row(title: "Restart a hung Notification Center",
                        note: state(restartState(h), ok: !h.ncStillHung)
                            + (canDetectHang ? " Restarts it when it shows no banners. Nothing is lost." : " The switch needs Instant banners and Instant app icons.")) {
                        HStack(spacing: 8) {
                            Button("Restart") { actions.restartNotificationCenter() }
                            Switch(on: config.ncAutoRestart) { actions.write("nc_auto_restart", $0 ? .bool(true) : nil, .table(["notifications"])) }
                                .disabled(!canDetectHang)
                        }
                    }
                    Row(title: "Open the exact chat",
                        note: "A click opens the right chat or thread, not just the app. Set each app in Apps.") {
                        Switch(on: config.openOriginal) { actions.write("open_original", $0 ? nil : .bool(false), .table(["notifications"])) }
                    }
                    Row(title: "Instant app icons",
                        note: state(!config.signal ? "Off." : h.lastSignal.map { "Last signal at \($0.formatted(date: .omitted, time: .shortened))." } ?? "No signal since Gzyms started.",
                                    ok: config.signal && h.lastSignal != nil)
                            + " The app's icon shows at once, the text follows.") {
                        Switch(on: config.signal) { actions.write("signal", $0 ? nil : .bool(false), .table(["notifications"])) }
                    }
                    Row(title: "Notifications from other apps",
                        note: state(fullDisk ? "Full Disk Access is on." : "Full Disk Access is off.", ok: fullDisk)
                            + " Needs Full Disk Access.") {
                        Button("Permissions") { actions.openGrant(.fullDiskAccess) }
                    }
                    Row(title: "How these work", note: "What each hack rests on and what a macOS update can break.") { docsButton }
                }
            }
        }
        .busy("settings: hacks, every 2 s", while: live)
    }

    /// The hang guard counts deliveries without a banner: it needs both (`AppDelegate.countSignal`).
    private var canDetectHang: Bool { config.bannerAX && config.signal }

    private var fullDisk: Bool { grants.first { $0.grant == .fullDiskAccess }?.granted == true }

    private func bannersState(_ h: HacksState) -> String {
        if !config.bannerAX { return "Off." }
        if h.nannyRunning { return "NotificationNanny is running. Quit it, it takes the same banners." }
        if h.noBanners { return Self.noBannersText }
        if !h.bannerAXOn { return "Waiting for Accessibility and Notification Center." }
        return h.lastBanner.map { "Last banner at \($0.formatted(date: .omitted, time: .shortened))." } ?? "No banner since Gzyms started."
    }

    static let noBannersText = "Notification Center shows no banners although apps send them, or a Focus is on. Restart it with the button, or: killall NotificationCenter"

    private func restartState(_ h: HacksState) -> String {
        var s = config.ncAutoRestart ? "Automatic restart on." : "Automatic restart off."
        if let at = h.ncLastRestart { s += " Restarted \(h.ncRestarts) time(s), last at \(at.formatted(date: .omitted, time: .shortened))." }
        if h.ncStillHung { s += " No banner since, so it will not restart again by itself." }
        return s
    }

    private var docsButton: some View { Button("Docs") { actions.openURL(Self.docs) } }

    private func state(_ text: String, ok: Bool) -> String { (ok ? "✓ " : "○ ") + text }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    let config: GzymsConfig
    let actions: SettingsActions
    @State private var tested: String?
    @Environment(\.theme) private var theme
    private var write: (String, TOMLValue?, ConfigTable) -> Void { actions.write }
    private static let phoneTable = ConfigTable.table(["notifications", "phone"])
    private static let afters: [(Int, String)] = [(0, "at once"), (1, "after 1 min"), (2, "after 2 min"), (5, "after 5 min"),
                                                  (10, "after 10 min"), (15, "after 15 min"), (30, "after 30 min")]
    private static let times: [(Double, String)] = [(4, "4 s"), (6, "6 s"), (8, "8 s"), (12, "12 s"), (30, "30 s"), (0, "until clicked")]

    var body: some View {
        Columns {
        Section(title: "Levels") {
            ForEach([NotifyLevel.info, .warning, .error, .critical], id: \.self) { l in
                Row(title: l.rawValue) {
                    menu(config.levelSeconds[l].flatMap { $0 } ?? 0, Self.times, width: 130) {
                        write(l.rawValue, .int(Int($0)), .table(["notifications", "levels"]))
                    }
                }
            }
            Row(title: "armageddon") { Text("until clicked (always)").foregroundStyle(theme[\.red]) }
        }
        Section(title: "Sound") {
            Row(title: "Sounds") { Switch(on: config.notificationSounds) { write("sounds", .bool($0), .table(["notifications"])) } }
            Row(title: "Sound at once", note: "The rest sounds when it gets into the stack. With a full stack it waits in its list.") {
                HStack(spacing: 4) {
                    ForEach(DNDBreak.allCases, id: \.self) { b in
                        breakChip(b, config.priority, DNDBreak.priorityDefaults, key: "priority", table: "notifications")
                    }
                }
            }
        }
        Section(title: "Do Not Disturb") {
            Row(title: "Still shows", note: "Turn it on with the moon on the bar. The rest waits in its list.") {
                HStack(spacing: 4) { ForEach(DNDBreak.allCases, id: \.self) { b in breakChip(b, config.dndBreaks, DNDBreak.defaults, key: "breaks_through", table: "dnd") } }
            }
        }
        Section(title: "Not answered on the Mac") {
            Row(title: "Send through", note: Self.formatNotes[config.phone.format]) {
                menu(config.phone.format, [(PushFormat.ntfy, "ntfy"), (.json, "JSON webhook"), (.pushover, "Pushover")], width: 150) {
                    write("format", $0 == .ntfy ? nil : .string($0.rawValue), Self.phoneTable)
                }
            }
            if config.phone.format == .pushover {
                Row(title: "User key", note: Self.saved(config.phone.pushoverUser) ?? "On pushover.net, top of the page after you log in") {
                    field("pushover_user", config.phone.pushoverUser, secure: true)
                }
                Row(title: "API token", note: Self.saved(config.phone.pushoverToken) ?? "Create an application on pushover.net, then copy its token") {
                    field("pushover_token", config.phone.pushoverToken, secure: true)
                }
            } else {
                Row(title: "Send to", note: config.phone.format == .ntfy ? "An ntfy topic like https://ntfy.sh/your-topic. Empty turns it off." : "The webhook address. Empty turns it off.") {
                    field("url", config.phone.url)
                }
            }
            Group {
                Row(title: "Send it", note: "when nobody opened, dismissed or snoozed it by then") {
                    menu(Int(config.phone.after / 60), Self.afters, width: 150) { write("after", $0 == 5 ? nil : .int($0), Self.phoneTable) }
                }
                Row(title: "Levels", note: "Plus apps with Phone on") {
                    HStack(spacing: 4) { ForEach(NotifyLevel.allCases, id: \.self) { l in levelChip(l) } }
                }
                Row(title: "Try it", note: tested) {
                    Button("Send test") { tested = "Sending…"; actions.testPhone { tested = $0 } }
                }
            }
        }
        }
    }

    private static let formatNotes: [PushFormat: String] = [
        .ntfy: "Title, text and priority for an ntfy topic",
        .json: "One JSON object with title, body, level, app and link. Tina, n8n or Home Assistant can take it.",
        .pushover: "High priority for critical and armageddon. The keys stay in config.toml as plain text.",
    ]

    /// A key that is set says so, with its last four characters to tell keys apart.
    private static func saved(_ key: String?) -> String? { key.map { "Saved, ends in \($0.suffix(4)). Paste a new one to replace it." } }

    private func field(_ key: String, _ value: String?, secure: Bool = false) -> some View {
        CommitField(text: value ?? "", secure: secure) { u in
            let t = u.trimmingCharacters(in: .whitespaces)
            write(key, t.isEmpty ? nil : .string(t), Self.phoneTable)
        }
        .frame(width: 260)
    }

    /// Click to add or take out a kind. Back at the defaults, the line leaves the file.
    private func breakChip(_ b: DNDBreak, _ current: Set<DNDBreak>, _ defaults: Set<DNDBreak>, key: String, table: String) -> some View {
        chip(b.rawValue, on: current.contains(b)) {
            var set = current
            if set.contains(b) { set.remove(b) } else { set.insert(b) }
            write(key, set == defaults ? nil : .strings(DNDBreak.allCases.filter(set.contains).map(\.rawValue)), .table([table]))
        }
    }

    private func levelChip(_ l: NotifyLevel) -> some View {
        chip(l.rawValue, on: config.phone.levels.contains(l)) {
            var set = config.phone.levels
            if set.contains(l) { set.remove(l) } else { set.insert(l) }
            let names = NotifyLevel.allCases.filter(set.contains).map(\.rawValue)
            write("levels", set == PhonePush().levels ? nil : .strings(names), Self.phoneTable)
        }
    }

    private func chip(_ text: String, on: Bool, flip: @escaping () -> Void) -> some View {
        Text(text)
            .lineLimit(1).fixedSize()
            .font(.system(size: 11, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? theme[\.base] : theme[\.text])
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(on ? theme[\.mauve] : theme[\.surface]))
            .onTapGesture(perform: flip)
            .settingsSlot(choose: flip)
            .pointerStyle(.link)
    }

}

/// Which apps may show what, and how macOS should hand their notifications over. A short list (apps that need a change
/// in macOS first, the rest folded), a click opens the app on the side (Greg, 2026-11-04: layout X).
private struct AppsTab: View {
    let config: GzymsConfig
    let apps: [SeenApp]
    let plugins: [PluginStatus]
    let actions: SettingsActions
    let live: Bool
    @State var selected: String?
    @State private var showOK = false
    @State private var dropping = false
    @Environment(\.theme) private var theme

    var body: some View {
        Columns {
        Section(title: "Apps") {
            if !needing.isEmpty {
                HStack {
                    Text("\(needing.count) \(needing.count == 1 ? "app needs" : "apps need") a change in macOS.").foregroundStyle(theme[\.peach])
                    Spacer()
                    let fixable = needing.filter { $0.mac?.pageDone == false }.map(\.id)
                    if !fixable.isEmpty { Button("Set up step by step") { actions.setUpApps(fixable) } }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme[\.peach].opacity(0.12)))
                .padding(.horizontal, 8).padding(.top, 8)
            }
            ForEach(listed.filter { !isOK($0) }, id: \.id, content: row)
            let ok = listed.filter(isOK)
            if !ok.isEmpty {
                if showOK { ForEach(ok, id: \.id, content: row) } else {
                    Button("\(ok.count) \(ok.count == 1 ? "app" : "apps") set up right") { showOK = true }
                        .buttonStyle(.borderless).foregroundStyle(theme[\.overlay])
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            if !plugins.isEmpty {
                Text("Plugins").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 8)
                ForEach(plugins.map { SeenApp(id: "plugin:\($0.folder)", name: $0.name, icon: nil) }, id: \.id, content: row)
            }
            HStack {
                Text("Drag an app here to set it up before it sends anything")
                    .foregroundStyle(theme[\.overlay])
                Text("or")
                Button("Choose app…", action: actions.chooseApp)
            }
            .frame(maxWidth: .infinity).padding(14)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(dropping ? theme[\.mauve] : theme[\.overlay].opacity(0.5),
                                                                       style: StrokeStyle(lineWidth: 1, dash: [4])))
            .padding(10)
            .dropDestination(for: URL.self) { urls, _ in
                urls.filter { $0.pathExtension == "app" }.forEach(actions.dropApp)
                return true
            } isTargeted: { dropping = $0 }
        }
        if let app = (listed + plugins.map { SeenApp(id: "plugin:\($0.folder)", name: $0.name, icon: nil) }).first(where: { $0.id == selected }) {
            Section(title: app.name) {
                AppDrawer(app: app, rule: config.appRules[app.id] ?? AppRule(), dnd: config.dndBreaks, live: live, write: actions.write,
                          readable: listed.contains { $0.mac != nil },
                          macOS: app.id.hasPrefix("plugin:") ? nil : { actions.openAppNotifications(app.id) },
                          forget: { selected = nil; actions.forgetApp(app.id) })
            }
        }
        }
    }

    /// Read from macOS and nothing to change. Apps not read (no Full Disk Access) stay in the list.
    private func isOK(_ a: SeenApp) -> Bool { a.mac?.problems.isEmpty == true }
    private var needing: [SeenApp] { listed.filter { !($0.mac?.problems.isEmpty ?? true) } }

    private func row(_ app: SeenApp) -> some View {
        let rule = config.appRules[app.id] ?? AppRule()
        let pick = { selected = selected == app.id ? nil : app.id }
        return HStack(spacing: 10) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable() } else { Color.clear }
            }
            .frame(width: 18, height: 18)
            Text(app.name).lineLimit(1)
            Spacer()
            Text(AppPreset(rule)?.title ?? "Custom").font(.system(size: 12)).foregroundStyle(theme[\.overlay])
            if let mac = app.mac, !mac.unsupported, !mac.hidden {
                let n = mac.problems.count
                HStack(spacing: 5) {
                    Circle().fill(n == 0 ? theme[\.green] : theme[\.peach]).frame(width: 7, height: 7)
                    Text(n == 0 ? "OK" : "\(n) in macOS")
                }
                .font(.system(size: 12)).foregroundStyle(n == 0 ? theme[\.overlay] : theme[\.peach])
                .frame(width: 84, alignment: .leading)
            } else {
                Color.clear.frame(width: 84, height: 1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected == app.id ? theme[\.surface] : .clear).padding(.horizontal, 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .settingsSlot(choose: pick)
        .help(app.mac?.warning ?? "")
    }

    /// Seen apps plus apps with a rule, by name.
    private var listed: [SeenApp] {
        // A rule back at its defaults (an app removed from the list leaves its empty table) lists nothing.
        let ruled = config.appRules.filter { id, rule in !id.hasPrefix("plugin:") && rule != AppRule() && !apps.contains { $0.id == id } }
            .keys.map { SeenApp(id: $0, name: $0, icon: nil) }
        return (apps + ruled).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension AppPreset {
    var title: String {
        switch self {
        case .full: "Banner and sound"
        case .quiet: "Quiet"
        case .count: "Count only"
        case .important: "Important"
        case .off: "Off"
        }
    }

    func note(dnd: Set<DNDBreak>) -> String {
        switch self {
        case .full: "Banner, Gzyms sound and a count on the bar."
        case .quiet: "Banner without sound. A count on the bar."
        case .count: "No banner and no sound. An icon with a number on the bar."
        case .important: dnd.contains(.critical)
            ? "Like Banner and sound, as critical. It breaks through Do Not Disturb."
            : "Like Banner and sound, as critical. Tick critical under Do Not Disturb in Notifications to break through it."
        case .off: "Gzyms skips it. Nothing shows and nothing lands in the list."
        }
    }
}

/// One app on the side of Settings → Apps: how Gzyms shows it, every switch under More, its macOS page below.
private struct AppDrawer: View {
    let app: SeenApp
    let rule: AppRule
    let dnd: Set<DNDBreak>
    let live: Bool
    let write: (String, TOMLValue?, ConfigTable) -> Void
    /// macOS settings are read for other apps: one without any has no page there.
    let readable: Bool
    /// Opens the app's macOS notification page; nil for plugins, which have none.
    var macOS: (() -> Void)?
    var forget: (() -> Void)?
    @State private var more = false
    @Environment(\.theme) private var theme

    private var table: ConfigTable { .table(["notifications", "apps", app.id]) }
    /// A value back at its default removes the line, so the file only says what differs.
    private func set(_ key: String, _ on: Bool) { write(key, on ? nil : .bool(false), table) }

    private func apply(_ p: AppPreset) {
        let r = p.applied(to: rule)
        set("banner", r.banner); set("sound", r.sound); set("count", r.count)
        write("level", r.level == .normal ? nil : .string(r.level.rawValue), table)
        write("skip", r.skip ? .bool(true) : nil, table)
    }

    var body: some View {
        let preset = AppPreset(rule)
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(get: { preset }, set: { if let p = $0 { apply(p) } })) {
                ForEach(AppPreset.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .settingsSlot { apply(AppPreset.allCases[((preset.flatMap { AppPreset.allCases.firstIndex(of: $0) } ?? -1) + 1) % AppPreset.allCases.count]) }
            .help(preset?.note(dnd: dnd) ?? "Custom. Set by hand under More.")
        }
        .padding(12)
        DisclosureGroup(isExpanded: $more) {
            VStack(spacing: 0) {
                Row(title: "Banner") { Switch(on: rule.banner) { set("banner", $0) } }
                Row(title: "Sound") { Switch(on: rule.sound) { set("sound", $0) } }
                Row(title: "Count on the bar") { Switch(on: rule.count) { set("count", $0) } }
                Row(title: "Phone") {
                    Switch(on: rule.phone) { write("phone", $0 ? .bool(true) : nil, table) }
                }
                Row(title: "Every notification is", note: rule.level == .armageddon ? "Every screen flashes red with a sound until you click it." : nil) {
                    menu(rule.level, [(AppLevel.normal, "normal"), (.critical, "critical"), (.armageddon, "armageddon")], width: 150) { l in
                        write("level", l == .normal ? nil : .string(l.rawValue), table)
                    }
                }
                Row(title: "Skip it") { Switch(on: rule.skip) { write("skip", $0 ? .bool(true) : nil, table) } }
            }
        } label: {
            Text("More").onTapGesture { more.toggle() }.settingsSlot { more.toggle() }
        }
        .padding(.horizontal, 12)
        if let macOS {
            HStack {
                if let forget { Button("Remove from list", action: forget) }
                Spacer()
                if app.mac.map({ !$0.hidden }) ?? !readable { Button("Open in System Settings", action: macOS) }
            }
            .padding(.horizontal, 12).padding(.top, 6)
            if let mac = app.mac, mac.hidden {
                Text("macOS has no settings page for it.").font(.system(size: 11)).foregroundStyle(theme[\.overlay]).padding(12)
            } else if let mac = app.mac, mac.unsupported {
                Text(mac.warning ?? "").padding(12)
            } else if let mac = app.mac {
                MacMirror(settings: mac, animate: live).id(app.id).padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                Text(readable ? "macOS has no settings for this app. It may be gone." : "Needs Full Disk Access to read macOS.")
                    .font(.system(size: 11)).foregroundStyle(theme[\.overlay]).padding(12)
            }
        }
    }
}

/// An app's page in System Settings → Notifications, drawn as macOS 27 draws it: the same cards, rows and order, so the
/// switch to click is found by where it sits (Greg, 2026-11-04: variant A). What to change is ringed and says what to do.
/// nil = the page as Gzyms wants it.
struct MacMirror: View {
    let settings: NCAppSettings?
    var animate = true
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var still

    private var shown: NCAppSettings { settings ?? NCAppSettings() }
    private func wrong(_ bad: Bool) -> Bool { settings != nil && bad }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            card { row("Allow notifications", fix: wrong(!shown.allowed) ? "Turn on" : nil) { toggle(shown.allowed) } }
            card {
                HStack(alignment: .top, spacing: 12) {
                    tile("Desktop", on: shown.desktop, fix: wrong(!shown.desktop) ? "Tick" : nil)
                    tile("Notification Center", on: shown.center, fix: wrong(!shown.center) ? "Tick" : nil)
                    tile("Lock Screen", on: nil, fix: nil)
                }
                .frame(maxWidth: .infinity)
                Divider()
                row("Alert Style", fix: nil) {
                    HStack(spacing: 10) {
                        radio("Temporary", on: settings.map { !$0.persistent })
                        radio("Persistent", on: settings.map(\.persistent))
                    }
                }
            }
            if shown.hasBadge || shown.hasSound {
                card {
                    if shown.hasBadge { row("Badge application icon", fix: nil) { toggle(nil) } }
                    if shown.hasBadge && shown.hasSound { Divider() }
                    if shown.hasSound { row("Play sound for notification", fix: wrong(shown.sound) ? "Turn off" : nil) { toggle(shown.sound) } }
                }
            }
            card {
                row("Show previews", fix: wrong(shown.previewsHidden)
                    ? (shown.previews == 0 ? "Pick When Unlocked" : "Pick Default")
                    : nil) {
                    HStack(spacing: 4) {
                        Text(["Default", "Never", "When Unlocked", "Always"][min(max(shown.previews, 0), 3)])
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                    .font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                }
                Divider()
                row("Notification grouping", fix: nil) { Text("either").font(.system(size: 11)).foregroundStyle(theme[\.overlay]) }
                Divider()
                row("Summarize notifications", fix: nil) { toggle(nil) }
            }
            if wrong(shown.shortcutOff) {
                Text("Turn on Show Notification Center (🌐 N) in System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Gzyms presses it to reach a notification whose banner is already gone.")
                    .font(.system(size: 11)).foregroundStyle(theme[\.peach])
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme[\.surface].opacity(0.7)))
    }

    /// The ring around what to change; it pulses only while `animate` (Settings on screen).
    @ViewBuilder private func ring(_ on: Bool) -> some View {
        if on, animate, !still { PulsingRing(color: theme[\.peach]) }
        else if on { RoundedRectangle(cornerRadius: 6).strokeBorder(theme[\.peach], lineWidth: 2.5) }
    }

    /// nil = either way.
    private func tile(_ title: String, on: Bool?, fix: String?) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4).fill(theme[\.base]).frame(width: 76, height: 44)
            Text(title).font(.system(size: 11)).lineLimit(1).fixedSize()
            Image(systemName: on == false ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(on == nil ? theme[\.overlay] : settings == nil ? theme[\.green] : theme[\.text])
            if let fix { Text(fix).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme[\.peach]) }
        }
        .padding(4)
        .overlay(ring(fix != nil))
    }

    private func row<V: View>(_ title: String, fix: String?, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                value()
            }
            if let fix { Text(fix).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme[\.peach]) }
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .overlay(ring(fix != nil))
    }

    /// A macOS switch. nil = either way. On the page as Gzyms wants it, a wanted on is green.
    private func toggle(_ on: Bool?) -> some View {
        let fill = on == true ? (settings == nil ? theme[\.green] : theme[\.sky]) : theme[\.overlay].opacity(on == nil ? 0.25 : 0.5)
        return Capsule().fill(fill).frame(width: 26, height: 15)
            .overlay(alignment: on == true ? .trailing : .leading) { Circle().fill(.white.opacity(on == nil ? 0.5 : 1)).padding(2) }
            .help(on == nil ? "Either way" : on! ? "On" : "Off")
    }

    private func radio(_ title: String, on: Bool?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: on == true ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(on == true ? theme[\.sky] : theme[\.overlay])
            Text(title).foregroundStyle(theme[\.overlay])
        }
        .font(.system(size: 11))
    }
}

/// A repeatForever cannot be stopped by changing its value back, and keeps ticking in an ordered-out window
/// (~5% CPU after Settings closed, 2026-11-05). Taking this view out of the tree is what stops it.
private struct PulsingRing: View {
    let color: Color
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 2.5)
            .opacity(dim ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(), value: dim)
            .onAppear { dim = true }
            .busy("settings: apps mirror pulse")
    }
}

/// A key cap: click it, press a letter. Writes `[keys.verbs]`.
private struct LetterRow: View {
    let title: String, key: String, letter: String
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    @State private var recording = false
    @State private var warning: String?
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.settingsNav) private var nav

    private func record() { recording = true; focused = true; warning = nil }

    /// Ctrl+letter that HyprMac or a terminal already means something by. Taken only while a banner is up.
    private static let busy: [String: String] = [
        "s": "HyprMac's scratchpad", "c": "interrupt in a terminal", "d": "end of input in a terminal",
        "i": "tab in a terminal", "n": "the next history line in a terminal", "p": "the previous history line in a terminal",
    ]

    /// A held modifier leader takes the letter from the apps while a banner is up.
    private var busyNote: String? {
        switch config.leader {
        case .modifier("ctrl")?: Self.busy[letter].map { "Ctrl+\(letter.uppercased()) is also \($0)" }
        case .modifier("cmd")?: "⌘\(letter.uppercased()) belongs to apps. Gzyms takes it only while a banner is up."
        case .modifier("alt")?: "⌥\(letter.uppercased()) types a special character. Gzyms takes it only while a banner is up."
        default: nil
        }
    }

    var body: some View {
        Row(title: title, note: warning ?? busyNote) {
            Text(recording ? "press a letter" : letter.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(recording ? theme[\.mauve].opacity(0.4) : theme[\.surface]))
                .focusable()
                .focused($focused)
                .onTapGesture(perform: record)
                .settingsSlot(choose: record)
                // Its letter comes as a key press: the panel's own keys stand aside meanwhile.
                .onChange(of: recording) { _, on in nav?.paused = on }
                .onKeyPress { press in
                    guard recording else { return .ignored }
                    recording = false
                    let c = press.characters.lowercased()
                    guard c.count == 1, ("a"..."z").contains(c), !KeyNav.fixedVerbs.contains(c) else {
                        warning = "Pick a letter a to z, not h j k l f"
                        return .handled
                    }
                    if let clash = config.verbs.all.first(where: { $0.key != key && $0.letter == c }) {
                        warning = "Already used for \(clash.key)"
                        return .handled
                    }
                    write(key, .string(c), .table(["keys", "verbs"]))
                    return .handled
                }
        }
    }
}
