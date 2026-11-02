import AppKit
import GzymsCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Sendable {
    case general, appearance, themes, notifications, modules, plugins, calendar, agents, sounds, shortcuts, permissions, debug, about
    public var title: String { self == .modules ? "Order" : rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// An app on the Notifications list: seen sending something, or set up by hand.
public struct SeenApp: Equatable {
    public var id: String, name: String
    public var icon: NSImage?
    public init(id: String, name: String, icon: NSImage?) { self.id = id; self.name = name; self.icon = icon }
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
    /// A plugin folder from disk, dropped or chosen: copied into the plugins folder. Returns what went wrong, if anything.
    public var installPlugin: (URL) -> String? = { _ in nil }
    public var choosePlugin: () -> Void = {}
    public var dropApp: (URL) -> Void = { _ in }
    public var revealConfig: () -> Void = {}
    public var openNotificationSettings: () -> Void = {}
    /// One app's own page in System Settings → Notifications, by bundle id.
    public var openAppNotifications: (String) -> Void = { _ in }
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
    public var version = "dev"
    public var openURL: (String) -> Void = { _ in }
    /// A shortcut recorder is listening: the keyboard tap stands aside.
    public var recording: (Bool) -> Void = { _ in }
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
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var width: CGFloat = 900
    @Environment(\.theme) private var theme
    @Environment(\.settingsNav) private var nav

    public init(tab: Binding<SettingsTab>, config: GzymsConfig, problems: [String], broken: Bool, apps: [SeenApp],
                devices: [String], workspaceNames: [Int: String] = [:], grants: [GrantState] = [], calendars: [CalendarInfo] = [],
                logo: NSImage? = nil, live: Bool = true, plugins: [PluginStatus] = [], actions: SettingsActions) {
        self.logo = logo; self.live = live; self.plugins = plugins
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

    /// Wide screens get sections side by side (Greg): one column per ~540 pt, up to three.
    private var columns: Int { max(1, min(3, Int((width - 48) / 540))) }

    @ViewBuilder private var header: some View {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    Text(t.title)
                        .font(.system(size: 13, weight: t == tab ? .semibold : .regular))
                        .foregroundStyle(t == tab ? theme[\.base] : theme[\.text])
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(t == tab ? theme[\.mauve] : theme[\.surface].opacity(0.0001)))
                        .contentShape(Capsule())
                        .onTapGesture { tab = t }
                }
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
        case .general: GeneralTab(config: config, names: workspaceNames, write: actions.write, reveal: actions.revealConfig)
        case .appearance: AppearanceTab(config: config, devices: devices, write: actions.write, openThemes: { tab = .themes })
        case .themes: ThemesTab(config: config, write: actions.write)
        case .notifications: NotificationsTab(config: config, apps: apps, plugins: plugins, actions: actions)
        case .modules: ModulesTab(config: config, write: actions.write, plugins: plugins)
        case .plugins: PluginsTab(config: config, write: actions.write, plugins: plugins, actions: actions)
        case .calendar: CalendarTab(config: config, calendars: calendars, write: actions.write)
        case .agents: AgentsTab(config: config, write: actions.write, plugins: plugins, actions: actions)
        case .sounds: SoundsTab(config: config, write: actions.write, actions: actions)
        case .shortcuts: ShortcutsTab(config: config, write: actions.write, recording: actions.recording)
        case .permissions: Section(title: "Permissions") { PermissionsView(states: grants, open: actions.openGrant, restart: actions.restart) }
        case .debug: DebugTab(config: config, actions: actions)
        case .about: AboutTab(version: actions.version, open: actions.openURL, config: config, logo: logo,
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
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(theme[\.overlay]) }
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
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let reveal: () -> Void

    var body: some View {
        Columns {
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
        Section(title: "Motion") {
            Row(title: "Animations", note: "banner unroll, icon flight, count bump") {
                Switch(on: config.animations) { write("animations", .bool($0), .table(["appearance"])) }
            }
            Row(title: "Follow macOS Reduce motion") {
                Switch(on: config.followReduceMotion) { write("follow_reduce_motion", .bool($0), .table(["appearance"])) }
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

/// Plugins from the plugins folder, one section each with its own form, and the ready ones from the catalog.
private struct PluginsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let plugins: [PluginStatus]
    let actions: SettingsActions
    @State private var dropping = false
    @State private var dropProblem: String?
    @Environment(\.theme) private var theme

    private var addable: [CatalogPlugin] { pluginCatalog.filter { c in !plugins.contains { $0.folder == c.name } } }

    var body: some View {
        Columns {
            ForEach(plugins, id: \.folder) { p in PluginSection(p: p, config: config, write: write, actions: actions) }
            Section(title: "Add a plugin") {
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
    }
}

/// One installed plugin: on or off, show, remove, and its own form drawn from the [[option]]s in its plugin.toml.
private struct PluginSection: View {
    let p: PluginStatus
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let actions: SettingsActions

    var body: some View {
        Section(title: p.name) {
            Row(title: p.enabled ? (p.running ? "On" : "Starting") : "Off", note: p.problem ?? (p.description.isEmpty ? p.folder : p.description)) {
                HStack(spacing: 8) {
                    Button("Show") { actions.revealPlugin(p.folder) }
                    Button("Remove") { actions.removePlugin(p.folder) }
                    Switch(on: p.enabled) { write("enabled", $0 ? nil : .bool(false), .table(["plugins", p.folder])) }
                }
            }
            ForEach(p.options, id: \.key) { o in
                PluginOptionRow(option: o, value: config.pluginOptions[p.folder]?[o.key] ?? o.defaultValue) { v in
                    write(o.key, v == o.defaultValue ? nil : v, .table(["plugins", p.folder]))
                }
            }
        }
    }
}

/// The agents plugin's own place: its settings when it is there, an Add button when not.
private struct AgentsTab: View {
    let config: GzymsConfig
    let write: (String, TOMLValue?, ConfigTable) -> Void
    let plugins: [PluginStatus]
    let actions: SettingsActions
    @Environment(\.theme) private var theme

    var body: some View {
        Columns {
            if let p = plugins.first(where: { $0.folder == "agents" }) {
                PluginSection(p: p, config: config, write: write, actions: actions)
            } else if let c = pluginCatalog.first(where: { $0.name == "agents" }) {
                Section(title: "Agents") {
                    Row(title: "Agents from tuios", note: c.summary) { Button("Add") { actions.addPlugin(c.name) } }
                }
            }
            Section(title: "Coming later") {
                Text("Claude Code and Codex without tuios. Any other tool through gzyms agent set.")
                    .font(.system(size: 12)).foregroundStyle(theme[\.overlay])
                    .padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
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
                Row(title: "Version \(version)", note: "Updates come with the first release.") { EmptyView() }
                Row(title: "Website") { Button("gzyms.dev") { open("https://gzyms.dev") } }
                Row(title: "Source") { Button("GitHub") { open("https://github.com/zalewskigrzegorz/gzyms") } }
                Row(title: "Changes") { Button("Changelog") { open("https://github.com/zalewskigrzegorz/gzyms/commits/main") } }
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
                Row(title: "Gzyms", note: "Open source. The license is picked before the first release.") { EmptyView() }
                // shortcut: listed by hand, generate from Package.resolved once there is a second dependency.
                Row(title: "TOMLDecoder", note: "Daniel Duan, MIT") { Button("Source") { open("https://github.com/dduan/TOMLDecoder") } }
            }
        }
    }
}

// MARK: - Debug

private struct DebugTab: View {
    let config: GzymsConfig
    let actions: SettingsActions
    @State private var reported: String?

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
                Row(title: "Report a problem", note: reported ?? "One zip on the Desktop: log, anomalies, config and versions. No notification text.") {
                    Button("Make report…") {
                        reported = actions.report().map { "Saved as \($0.lastPathComponent) on the Desktop. Send it to Greg." }
                            ?? "Could not make the report. The log says why."
                    }
                }
                Row(title: "Missing something?") { Button("Request a feature…", action: actions.requestFeature) }
            }
        }
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    let config: GzymsConfig
    let apps: [SeenApp]
    let plugins: [PluginStatus]
    let actions: SettingsActions
    @State private var dropping = false
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
        Section(title: "Apps") {
            HStack {
                Text("App"); Spacer(); Color.clear.frame(width: 24)
                Text("Banner").frame(width: 56); Text("Sound").frame(width: 56); Text("Count").frame(width: 56)
                Text("Phone").frame(width: 56)
                Text("Every notification is").frame(width: 150)
            }
            .font(.system(size: 11)).foregroundStyle(theme[\.overlay]).padding(.horizontal, 12).padding(.top, 6)
            ForEach(listed, id: \.id) { app in
                AppRow(app: app, rule: config.appRules[app.id] ?? AppRule(), write: write) { actions.openAppNotifications(app.id) }
            }
            if !plugins.isEmpty {
                Text("Plugins").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 8)
                ForEach(plugins, id: \.folder) { p in
                    let id = "plugin:\(p.folder)"
                    AppRow(app: SeenApp(id: id, name: p.name, icon: nil), rule: config.appRules[id] ?? AppRule(), write: write)
                }
                Divider().padding(.horizontal, 12).padding(.top, 4)
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
        Section(title: "macOS") {
            Row(title: "Let Gzyms show them, not macOS",
                note: "The gear next to an app opens its macOS page. Keep Allow notifications and Badge on. Untick Desktop, Notification Center and Lock Screen, and turn the sound off. Gzyms still gets every one, and nothing shows twice.") {
                Button("Open Notification settings", action: actions.openNotificationSettings)
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

    /// Seen apps plus apps with a rule, by name.
    private var listed: [SeenApp] {
        let ruled = config.appRules.keys.filter { id in !id.hasPrefix("plugin:") && !apps.contains { $0.id == id } }.map { SeenApp(id: $0, name: $0, icon: nil) }
        return (apps + ruled).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

private struct AppRow: View {
    let app: SeenApp
    let rule: AppRule
    let write: (String, TOMLValue?, ConfigTable) -> Void
    /// Opens the app's macOS notification page; nil for plugins, which have none.
    var macOS: (() -> Void)?
    @Environment(\.theme) private var theme

    private var table: ConfigTable { .table(["notifications", "apps", app.id]) }
    /// A value back at its default removes the line, so the file only says what differs.
    private func set(_ key: String, _ on: Bool) { write(key, on ? nil : .bool(false), table) }

    var body: some View {
        HStack {
            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(app.name).lineLimit(1)
            Spacer()
            Group {
                if let macOS { Button(action: macOS) { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Its macOS notification settings") }
            }
            .frame(width: 24)
            Switch(on: rule.banner) { set("banner", $0) }.frame(width: 56)
            Switch(on: rule.sound) { set("sound", $0) }.frame(width: 56)
            Switch(on: rule.count) { set("count", $0) }.frame(width: 56)
            Switch(on: rule.phone) { write("phone", $0 ? .bool(true) : nil, table) }.frame(width: 56)
            menu(rule.level, [(AppLevel.normal, "normal"), (.critical, "critical"), (.armageddon, "armageddon")], width: 150) { l in
                write("level", l == .normal ? nil : .string(l.rawValue), table)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .help(rule.level == .armageddon ? "Every screen flashes red with a sound until you click it." : "")
    }
}
