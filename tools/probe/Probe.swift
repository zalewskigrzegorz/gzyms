import AppKit
import Network
import SwiftUI
import UserNotifications

/// Sends real macOS notifications, sets its own Dock badge, runs every `gzyms` CLI command,
/// spawns pretend meetings, and shows what Gzyms logged about it all.
@main
struct ProbeApp: App {
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    var body: some Scene {
        Window("Gzyms Probe", id: "probe") { ProbeView().frame(minWidth: 760, minHeight: 560) }
    }
}

enum ProbeTab: String, CaseIterable, Identifiable {
    case gallery, themes, notifications, cli, meetings, plugins, media, hacks, logs
    var id: Self { self }

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .themes: "Themes"
        case .notifications: "Notifications"
        case .cli: "CLI"
        case .meetings: "Meetings"
        case .plugins: "Plugins"
        case .media: "Media"
        case .hacks: "Hacks"
        case .logs: "Logs"
        }
    }

    var icon: String {
        switch self {
        case .gallery: "square.grid.2x2"
        case .themes: "paintpalette"
        case .notifications: "bell"
        case .cli: "terminal"
        case .meetings: "video"
        case .plugins: "puzzlepiece.extension"
        case .media: "play.rectangle"
        case .hacks: "wrench.and.screwdriver"
        case .logs: "doc.plaintext"
        }
    }

    /// What the search matches besides the title: the things on the tab.
    var keywords: [String] {
        switch self {
        case .gallery: ["look", "states", "release", "banner", "compact", "reminder", "theme", "settings tab", "set"]
        case .themes: ["theme", "colors", "palette", "dark", "light", "dracula", "nord", "catppuccin", "gruvbox", "tokyo"]
        case .notifications: ["macos", "send", "burst", "update", "delay", "dock", "badge", "banner", "island"]
        case .cli: ["gzyms", "notify", "level", "sound", "screen", "link", "theme", "hud", "version"]
        case .meetings: ["meeting-test", "calendar", "late", "starting now", "meet", "preview"]
        case .plugins: ["log watcher", "armageddon", "error", "fatal", "rule", "agents", "tuios"]
        case .media: ["music", "video", "browser", "userscript", "mediaremote", "spotify", "play", "pause"]
        case .hacks: ["media keys", "about:config", "hardwaremediakeys", "userscript", "violentmonkey", "music.app"]
        case .logs: ["log", "filter", "calendar", "mic", "notify", "nc", "dock", "chords", "anomalies"]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || title.lowercased().contains(q) || keywords.contains { $0.contains(q) }
    }
}

struct ProbeView: View {
    @State private var tab: ProbeTab? = .notifications
    @State private var query = ""

    private var shown: [ProbeTab] { ProbeTab.allCases.filter { $0.matches(query) } }

    var body: some View {
        NavigationSplitView {
            List(shown, selection: $tab) { t in Label(t.title, systemImage: t.icon).tag(t) }
                .searchable(text: $query, placement: .sidebar, prompt: "Go to…")
                // Return jumps to the first match, so typing "late" + Return lands on Meetings.
                .onSubmit(of: .search) { if let first = shown.first { tab = first } }
                .onChange(of: query) { if let first = shown.first, !shown.contains(where: { $0 == tab }) { tab = first } }
                .navigationSplitViewColumnWidth(170)
        } detail: {
            ScrollView {
                Group {
                    switch tab ?? .notifications {
                    case .gallery: GalleryTab()
                    case .themes: ThemesTab()
                    case .notifications: NotificationsTab()
                    case .cli: CLITab()
                    case .meetings: MeetingsTab()
                    case .plugins: PluginsTab()
                    case .media: MediaTab()
                    case .hacks: HacksTab()
                    case .logs: LogsTab()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle((tab ?? .notifications).title)
        }
        // Up from launch, so the userscript's tabs are heard whichever tab is open.
        .onAppear { MediaServer.shared.start() }
    }
}

// MARK: - Gallery

/// Every look Gzyms has, one click each, through the CLI only: the pass before a release (Greg, 2026-10-31).
/// The PNG patterns in Tests/GzymsUITests/Snapshots check the same looks without a screen.
struct GalleryTab: View {
    @State private var output = ""
    private typealias Item = (label: String, args: [String])

    private let banners: [Item] = [
        ("info", ["notify", "--level", "info", "--title", "Build finished", "--body", "gzyms in 41 s", "--sound", "success"]),
        ("warning", ["notify", "--level", "warning", "--title", "Disk almost full", "--body", "12 GB left on Macintosh HD"]),
        ("error", ["notify", "--level", "error", "--title", "Deploy failed", "--body", "api-eu: health check timed out after 30 s"]),
        ("critical", ["notify", "--level", "critical", "--title", "Prod is down", "--body", "api-eu answers 502"]),
        ("armageddon", ["notify", "--level", "armageddon", "--title", "Gallery armageddon", "--body", "Right click to dismiss"]),
        ("long body", ["notify", "--level", "error", "--title", "A title long enough to need the whole width of the island",
                       "--body", "A body that goes on: line after line of a stack trace, a path, an id, and a sentence that does not stop where it should."]),
        ("from an app", ["notify", "--app", "com.apple.mail", "--title", "Anna", "--body", "Lunch at one?"]),
        ("with a link", ["notify", "--title", "PR #42 approved", "--link", "https://github.com", "--alt-link", "https://gzyms.dev"]),
        ("compact", ["notify", "--compact", "--app", "com.apple.mail"]),
        ("reminder", ["notify", "--reminder", "--title", "Reminder", "--body", "Stays until you act on it"]),
    ]
    private let meetings: [Item] = [("in 4 min", ["meeting-test", "4"]), ("now", ["meeting-test", "0"]), ("3 min late", ["meeting-test", "-3"])]
    private let looks: [Item] = [
        ("animations off", ["set", "appearance.animations", "false"]), ("animations on", ["set", "appearance.animations", "true"]),
        ("small on notch", ["set", "workspaces.small_on_notch", "true"]), ("full size", ["set", "workspaces.small_on_notch", "false"]),
        ("CPU bars", ["set", "cpu.chart", "bars"]), ("CPU line", ["set", "cpu.chart", "line"]),
    ]
    private let tabs = ["general", "appearance", "themes", "notifications", "modules", "plugins", "calendar", "agents",
                        "sounds", "shortcuts", "permissions", "debug", "about"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Each button shows one state on the bar. Look at it, then the next one.")
                .font(.caption).foregroundStyle(.secondary)
            group("Banners", banners)
            group("Meetings", meetings)
            group("Look (writes config.toml, set it back with the pair)", looks)
            group("Settings tabs", tabs.map { ($0, ["settings", $0]) })
            group("HUD", [("open or close", ["hud"])])
            Text("Themes: the Themes tab. File shelf: drag a file anywhere. Agents and log watcher: the Plugins tab.")
                .font(.caption).foregroundStyle(.secondary)
            if !output.isEmpty { Output(text: output).foregroundStyle(.red) }
        }
    }

    private func group(_ title: String, _ items: [Item]) -> some View {
        GroupBox(title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading) {
                ForEach(items, id: \.label) { i in Button(i.label) { Gzyms.runQuietly(i.args) { output = $0 } } }
            }
        }
    }
}

// MARK: - Themes

/// Every theme Gzyms has, searchable, with its colours. A click puts it on the bar; ← and → step through the list.
struct ThemesTab: View {
    struct Row: Decodable, Identifiable {
        let name, base, surface, text, red, peach, gold, green, sky, mauve: String
        var id: String { name }
        var dark: Bool { Color.luminance(base) < 0.5 }
    }
    private struct List: Decodable { let current: String; let themes: [Row] }
    @State private var themes: [Row] = []
    @State private var current = ""
    @State private var query = ""
    @State private var shade = "all"
    @State private var error = ""

    private var shown: [Row] {
        themes.filter { t in
            (query.isEmpty || t.name.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "_")))
                && (shade == "all" || (shade == "dark") == t.dark)
        }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("search, e.g. tokyo", text: $query).frame(width: 220)
                Picker("", selection: $shade) {
                    Text("all").tag("all"); Text("dark").tag("dark"); Text("light").tag("light")
                }
                .pickerStyle(.segmented).frame(width: 250)
                Button("←") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("→") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Text("\(shown.count) of \(themes.count) · on: \(current). Favourites: Settings → Themes").foregroundStyle(.secondary)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(shown) { t in
                    HStack(spacing: 10) {
                        Text(t.name).frame(width: 240, alignment: .leading)
                        HStack(spacing: 3) {
                            Text("Aa").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: t.text)).frame(width: 30)
                            ForEach([t.red, t.peach, t.gold, t.green, t.sky, t.mauve], id: \.self) { c in
                                Circle().fill(Color(hex: c)).frame(width: 12, height: 12)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: t.base), in: RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(4)
                    .background(t.name == current ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { apply(t.name) }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: Gzyms.path)
        p.arguments = ["theme", "--json"]
        p.standardOutput = pipe
        do { try p.run() } catch { self.error = "gzyms: \(error)"; return }
        guard let list = try? JSONDecoder().decode(List.self, from: pipe.fileHandleForReading.readDataToEndOfFile()) else {
            error = "gzyms theme --json gave nothing readable"; return
        }
        themes = list.themes
        current = list.current
    }

    private func step(_ by: Int) {
        let list = shown
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.name == current }.map { ($0 + by + list.count) % list.count } ?? 0
        apply(list[i].name)
    }

    private func apply(_ name: String) {
        current = name
        Gzyms.runQuietly(["theme", name]) { error = $0 }
    }
}

extension Color {
    init(hex: String) {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
    }

    static func luminance(_ hex: String) -> Double {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return (0.299 * Double(v >> 16 & 255) + 0.587 * Double(v >> 8 & 255) + 0.114 * Double(v & 255)) / 255
    }
}

// MARK: - Notifications

struct NotificationsTab: View {
    @State private var title = "Anna"
    @State private var subtitle = "#gzyms"
    @State private var body_ = "looks good, ship it"
    @State private var badge = 3
    @State private var sent = 0
    @State private var delay = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("macOS notification") {
                VStack(alignment: .leading) {
                    TextField("title", text: $title)
                    TextField("subtitle", text: $subtitle)
                    TextField("body", text: $body_)
                    HStack {
                        Button("Send") { send() }
                        Button("Burst of 3") { for i in 1...3 { send(suffix: " \(i)") } }
                        Button("Update the last one") { send(id: "probe-update") }
                        Button("Remove delivered") { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
                    }
                    HStack {
                        Stepper("delay \(delay) s", value: $delay, in: 1...60)
                        // Time to switch to another app first, e.g. to click the island from there.
                        Button("Send in \(delay) s") { send(after: Double(delay)) }
                    }
                    Text("sent \(sent)").foregroundStyle(.secondary)
                }
            }
            GroupBox("Dock badge") {
                HStack {
                    Stepper("\(badge)", value: $badge, in: 1...120)
                    Button("Set") { NSApp.dockTile.badgeLabel = "\(badge)" }
                    Button("Set •") { NSApp.dockTile.badgeLabel = "•" }
                    Button("Clear") { NSApp.dockTile.badgeLabel = nil }
                }
            }
            GroupBox("Gzyms log (notify, nc, signal, dock, chords)") {
                LogTail(prefixes: ["notify:", "nc:", "signal:", "dock:", "chords:"]).frame(height: 200)
            }
        }
    }

    private func send(suffix: String = "", id: String = UUID().uuidString, after: Double? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title + suffix
        c.subtitle = subtitle
        c.body = body_
        let trigger = after.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
        sent += 1
    }
}

// MARK: - CLI

/// The `gzyms` CLI: every command and flag, run through the real binary in ~/.local/bin.
struct CLITab: View {
    @State private var title = "Build finished"
    @State private var subtitle = ""
    @State private var body_ = "All tests green."
    @State private var level = "info"
    @State private var app = ""
    @State private var link = ""
    @State private var altLink = ""
    @State private var sound = ""
    @State private var screen = ""
    @State private var id = ""
    @State private var output = ""
    private let levels = ["info", "warning", "error", "critical", "armageddon"]
    private let sounds = ["", "success", "fail", "waiting", "message"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("gzyms notify") {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("--title", text: $title)
                        TextField("--subtitle", text: $subtitle)
                    }
                    TextField("--body", text: $body_)
                    HStack {
                        Picker("--level", selection: $level) { ForEach(levels, id: \.self) { Text($0) } }
                        Picker("--sound", selection: $sound) { ForEach(sounds, id: \.self) { Text($0.isEmpty ? "none" : $0) } }
                        Picker("--screen", selection: $screen) {
                            Text("focus").tag("")
                            ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { Text($0).tag($0) }
                        }
                    }
                    HStack {
                        TextField("--app (bundle id, e.g. com.mitchellh.ghostty)", text: $app)
                        TextField("--id (same id updates)", text: $id)
                    }
                    HStack {
                        TextField("--link", text: $link)
                        TextField("--alt-link", text: $altLink)
                    }
                    Button("gzyms notify") { Gzyms.run(notifyArgs) { output = $0 } }.keyboardShortcut(.return, modifiers: .command)
                }
            }
            GroupBox("Other commands") {
                HStack {
                    Button("theme mocha-neon") { Gzyms.run(["theme", "mocha-neon"]) { output = $0 } }
                    Button("theme grayscale") { Gzyms.run(["theme", "grayscale"]) { output = $0 } }
                    Button("theme?") { Gzyms.run(["theme"]) { output = $0 } }
                    Divider().frame(height: 16)
                    // The HUD detaches itself; nothing to read back.
                    Button("hud on/off") { Gzyms.run(["hud"], quiet: true) { output = $0 } }
                    Button("--version") { Gzyms.run(["--version"]) { output = $0 } }
                }
            }
            Output(text: output)
        }
    }

    private var notifyArgs: [String] {
        var a = ["notify", "--title", title, "--level", level]
        for (flag, value) in [("--subtitle", subtitle), ("--body", body_), ("--app", app), ("--link", link),
                              ("--alt-link", altLink), ("--sound", sound), ("--screen", screen), ("--id", id)] where !value.isEmpty {
            a += [flag, value]
        }
        return a
    }
}

// MARK: - Meetings

/// `gzyms meeting-test`: a 15 min pretend meeting with a Meet link, never written to a calendar.
struct MeetingsTab: View {
    @State private var minutes = 2
    @State private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Pretend meeting (15 min, Meet link)") {
                VStack(alignment: .leading) {
                    HStack {
                        Button("in 3 min") { spawn(3) }
                        Button("starting now") { spawn(0) }
                        Button("1 min late") { spawn(-1) }
                        Button("5 min late") { spawn(-5) }
                        Button("almost over") { spawn(-13) }
                    }
                    HStack {
                        // Negative = it started that many minutes ago.
                        Stepper("start in \(minutes) min", value: $minutes, in: -14...30)
                        Button("Spawn") { spawn(minutes) }
                    }
                }
            }
            Output(text: output)
            GroupBox("Gzyms log (calendar, mic meter)") {
                LogTail(prefixes: ["calendar:", "mic meter:"]).frame(height: 260)
            }
        }
    }

    private func spawn(_ m: Int) { Gzyms.run(["meeting-test", String(m)]) { output = $0 } }
}

// MARK: - Plugins

/// The log watcher against a file Probe writes: each button appends one line, the plugin decides what it is.
struct PluginsTab: View {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Gzyms/probe-test.log")
    @State private var line = "prod down: api-eu 502"
    @State private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Log watcher") {
                VStack(alignment: .leading) {
                    HStack {
                        Button("Add the plugin") { Gzyms.run(["plugin", "add", "log-watcher"]) { output = $0 } }
                        Button("Copy the test file path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.file.path, forType: .string)
                            output = "copied \(Self.file.path)\npaste it into Settings → Plugins → Log watcher → Files"
                        }
                    }
                    Text("Default rules: ERROR or Exception = error, FATAL or PANIC = critical. Armageddon, warning and info are empty until you set them.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("info line") { append("info: probe says hello") }
                        Button("ERROR line") { append("ERROR db timeout after 30s") }
                        Button("FATAL line") { append("FATAL worker crashed") }
                        Button("3 ERRORs") { (1...3).forEach { append("ERROR burst \($0)") } }
                    }
                    HStack {
                        TextField("any line", text: $line)
                        Button("Append") { append(line) }
                    }
                }
            }
            GroupBox("Agents") {
                VStack(alignment: .leading) {
                    HStack {
                        Button("Add the plugin") { Gzyms.run(["plugin", "add", "agents"]) { output = $0 } }
                        Picker("agent", selection: $agent) {
                            ForEach(agents, id: \.window_id) { Text("\($0.session) · \($0.name) (\($0.state))").tag($0.window_id) }
                        }.frame(width: 420)
                        Button("Reload") { loadAgents() }
                    }
                    Text("tuios sets the state as if the agent had. The agent's own next hook sets it back. The 5 s give you time to switch apps.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Waits for you in 5 s") { setState("needs_input", note: "Probe: approve a test", after: 5) }
                        Button("Done in 5 s") { setState("done", after: 5) }
                        Button("Working now") { setState("working") }
                    }
                    Text("Done notifies only after a run as long as Done after (Settings → Agents). Set it to 0 to test.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear(perform: loadAgents)
            Output(text: output)
            GroupBox("Gzyms log (plugin, notify)") {
                LogTail(prefixes: ["plugin ", "notify:"]).frame(height: 260)
            }
        }
    }

    private struct Agent: Decodable { let window_id: String, session: String, name: String, state: String }
    @State private var agents: [Agent] = []
    @State private var agent = ""

    private func loadAgents() {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: Gzyms.tuios)
        p.arguments = ["list-agents", "--all-sessions", "--json"]
        p.standardOutput = pipe
        do { try p.run() } catch { output = "tuios: \(error)"; return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        struct List: Decodable { let agents: [Agent] }
        agents = (try? JSONDecoder().decode(List.self, from: data))?.agents ?? []
        if !agents.contains(where: { $0.window_id == agent }) { agent = agents.first?.window_id ?? "" }
    }

    private func setState(_ state: String, note: String = "", after: Double = 0) {
        guard let a = agents.first(where: { $0.window_id == agent }) else { output = "pick an agent first"; return }
        output = after > 0 ? "\(state) for \(a.name) in \(Int(after)) s" : ""
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            Gzyms.run(["set-agent-state", state, "-s", a.session, "-w", a.window_id] + (note.isEmpty ? [] : ["-m", note]), exe: Gzyms.tuios) { output = $0 }
        }
    }

    private func append(_ text: String) {
        let data = Data("\(Date().formatted(.iso8601)) \(text)\n".utf8)
        if let h = try? FileHandle(forWritingTo: Self.file) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: Self.file)
        }
        output = "appended to \(Self.file.lastPathComponent): \(text)"
    }
}

// MARK: - Logs

struct LogsTab: View {
    @State private var source = "all"
    @State private var filter = ""
    private let sources = ["all", "calendar:", "mic meter:", "notify:", "nc:", "dock:", "chords:", "signal:", "permissions:"]

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("source", selection: $source) { ForEach(sources, id: \.self) { Text($0) } }.frame(width: 220)
                TextField("contains…", text: $filter)
                Button("Open in Console") {
                    NSWorkspace.shared.open(LogTail.url)
                }
            }
            LogTail(prefixes: source == "all" ? [] : [source], contains: filter, count: 200).frame(minHeight: 420)
        }
    }
}

// MARK: - Media

/// Spike (2026-11-03): browser video through a userscript, music through MediaRemote and Music.app's AppleScript.
/// Needs media.hardwaremediakeys.enabled = false in the browser, so the media keys are left to the music player.
struct MediaTab: View {
    @ObservedObject private var server = MediaServer.shared
    @ObservedObject private var mr = MediaRemoteFeed.shared
    @State private var music = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Browser tabs (userscript)") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Open the install page") { NSWorkspace.shared.open(MediaServer.scriptURL) }
                        Button("Copy its URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(MediaServer.scriptURL.absoluteString, forType: .string)
                        }
                        Text(server.status).font(.caption).foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let tabs = server.live
                        if tabs.isEmpty { Text("No tab reports media yet.").foregroundStyle(.secondary) }
                        ForEach(tabs, id: \.id) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(t.title).lineLimit(1)
                                    Text(URL(string: t.url)?.host() ?? "").foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Go to") { server.send(t.id, 0, "focus") }
                                }
                                ForEach(t.media, id: \.i) { m in
                                    HStack {
                                        Image(systemName: m.playing ? "play.fill" : "pause.fill").frame(width: 16)
                                        Text("\(m.kind) #\(m.i)").foregroundStyle(.secondary)
                                        Button(m.playing ? "Pause" : "Play") { server.send(t.id, m.i, m.playing ? "pause" : "play") }
                                        Button("Next") { server.send(t.id, m.i, "next") }
                                    }
                                }
                                if !t.note.isEmpty { Text(t.note).font(.caption).foregroundStyle(.orange) }
                            }
                            .padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            GroupBox("MediaRemote (the media keys go to Now Playing)") {
                VStack(alignment: .leading, spacing: 6) {
                    if let now = mr.now {
                        HStack {
                            Image(systemName: now.playing ? "play.fill" : "pause.fill").frame(width: 16)
                            Text("\(now.appName): \(now.title)").lineLimit(1)
                            Spacer()
                            Button("Play/Pause") { mr.send(2) }
                            Button("Next") { mr.send(4) }
                        }
                    } else {
                        Text(mr.status.isEmpty ? "Nothing is Now Playing." : mr.status).foregroundStyle(.secondary)
                    }
                    ForEach(mr.others, id: \.app) { o in
                        HStack {
                            Image(systemName: o.playing ? "play.fill" : "pause.fill").frame(width: 16)
                            Text("\(o.appName): \(o.title)").lineLimit(1)
                            Spacer()
                            // macOS steers only Now Playing (send-commands is Control Center's), so others can only be gone to.
                            Button("Go to") { NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == o.app }?.activate() }
                        }
                    }
                }
            }
            GroupBox("Music.app (AppleScript)") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Play/Pause") { music(["playpause"]) }
                        Button("Next") { music(["next track"]) }
                        Button("State") { music([]) }
                        Text(music).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("A running Music.app takes the media keys when nothing else plays: quit it (cmd+Q) to give them to Spotifast.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { server.start(); mr.start() }
    }

    /// Never launches Music.app: a running one takes the media keys.
    private func music(_ command: [String]) {
        let tell = command.map { "tell application id \"com.apple.Music\" to \($0)\n" }.joined()
        let script = "if application id \"com.apple.Music\" is not running then return \"not running\"\n\(tell)"
            + "tell application id \"com.apple.Music\" to return player state as text"
        Gzyms.run(["-e", script], exe: "/usr/bin/osascript") { music = $0.components(separatedBy: "\n").dropFirst().joined(separator: " ") }
    }
}

/// What the bar's Settings → Hacks would be: each hack with its state, what the user does, and one button.
/// Read-only: the browser pref and the userscript install stay the user's own steps.
struct HacksTab: View {
    @ObservedObject private var server = MediaServer.shared
    private struct Pref: Identifiable { let browser, profile: String; let off: Bool; var id: String { browser + profile } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            VStack(alignment: .leading, spacing: 14) {
                hack("Media keys for the music player only",
                     state: prefs().map { "\($0.browser) \($0.profile): \($0.off ? "off ✓" : "on") " }.joined(separator: "· "),
                     done: !prefs().isEmpty && prefs().allSatisfy(\.off),
                     how: "In the browser open about:config and set media.hardwaremediakeys.enabled to false. The browser leaves Now Playing at once, no restart. Chromium: --disable-features=HardwareMediaKeyHandling.") {
                    Button("Copy the pref name") { copy("media.hardwaremediakeys.enabled") }
                }
                hack("Browser video through the userscript",
                     state: server.live.isEmpty ? "no tab reports media" : "\(server.live.count) tab(s) report media",
                     done: !server.live.isEmpty,
                     how: "Install Violentmonkey (or Tampermonkey), then open the script URL: the manager shows Install. Keep this app running, it serves the script and the tabs talk to it on 127.0.0.1 only.") {
                    Button("Open the install page") { server.start(); NSWorkspace.shared.open(MediaServer.scriptURL) }
                }
                hack("Music.app off the media keys",
                     state: musicRunning ? "Music.app is running" : "Music.app is not running",
                     done: !musicRunning,
                     how: "A running Music.app takes the media keys whenever the browser does not, even when it plays nothing. Quit it when you play from Spotify or Spotifast.") {
                    Button("Quit Music.app") { NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.Music" }?.terminate() }
                        .disabled(!musicRunning)
                }
            }
        }
        .onAppear { server.start() }
    }

    private var musicRunning: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" } }

    /// Every Gecko profile of Vimma and Firefox, from its prefs.js (only read).
    private func prefs() -> [Pref] {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ["Vimma", "Firefox"].flatMap { browser -> [Pref] in
            let dir = support.appendingPathComponent("\(browser)/Profiles")
            let profiles = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return profiles.compactMap { p in
                guard let text = try? String(contentsOf: dir.appendingPathComponent("\(p)/prefs.js"), encoding: .utf8) else { return nil }
                return Pref(browser: browser, profile: String(p.split(separator: ".").last ?? ""),
                            off: text.contains("user_pref(\"media.hardwaremediakeys.enabled\", false)"))
            }
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func hack(_ title: String, state: String, done: Bool, how: String, @ViewBuilder action: () -> some View) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? .green : .secondary)
                    Text(title).bold()
                    Spacer()
                    action()
                }
                Text(state).font(.caption).foregroundStyle(.secondary)
                Text(how).font(.caption)
            }
        }
    }
}

/// Loopback-only HTTP for the userscript: GET serves the script, POST /report takes a tab's media and answers its commands.
@MainActor final class MediaServer: ObservableObject {
    static let shared = MediaServer()
    static let port: UInt16 = 47100
    static let scriptURL = URL(string: "http://127.0.0.1:\(port)/gzyms-media.user.js")!

    struct Media: Decodable { let i: Int, kind: String, title: String, playing: Bool }
    struct Tab: Decodable { let id: String, url: String, title: String, note: String, media: [Media] }

    @Published var status = ""
    @Published private var tabs: [String: (tab: Tab, seen: Date)] = [:]
    private var pending: [String: [[String: Any]]] = [:]
    private var listener: NWListener?

    /// Tabs heard from in the last 3 s (the userscript reports every second), with media.
    var live: [Tab] {
        tabs.values.filter { $0.seen > .now - 3 && !$0.tab.media.isEmpty }.map(\.tab).sorted { $0.id < $1.id }
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        do { listener = try NWListener(using: params) } catch { status = "listen: \(error)"; return }
        listener?.stateUpdateHandler = { s in MainActor.assumeIsolated { self.status = "server \(s) on 127.0.0.1:\(Self.port)" } }
        listener?.newConnectionHandler = { c in
            MainActor.assumeIsolated {
                c.start(queue: .main)
                self.read(c, Data())
            }
        }
        listener?.start(queue: .main)
    }

    func send(_ tab: String, _ i: Int, _ cmd: String) { pending[tab, default: []].append(["i": i, "cmd": cmd]) }

    private func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
            MainActor.assumeIsolated {
                var b = buffer
                if let data { b.append(data) }
                if let reply = self.answer(b) { c.send(content: reply, completion: .contentProcessed { _ in c.cancel() }) }
                else if done || error != nil || b.count > 1 << 20 { c.cancel() }
                else { self.read(c, b) }
            }
        }
    }

    /// The whole HTTP response for a complete request, nil while the request is still arriving.
    private func answer(_ d: Data) -> Data? {
        guard let end = d.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: d[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let line = head[0].split(separator: " ")
        var headers: [String: String] = [:]
        for h in head.dropFirst() {
            if let colon = h.firstIndex(of: ":") { headers[h[..<colon].lowercased()] = h[h.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
        }
        let body = d[end.upperBound...]
        guard body.count >= Int(headers["content-length"] ?? "0") ?? 0 else { return nil }
        guard line.count >= 2 else { return http(400, "text/plain", Data()) }
        switch (line[0], line[1]) {
        case ("GET", "/gzyms-media.user.js"):
            guard let url = Bundle.main.url(forResource: "gzyms-media.user", withExtension: "js"), let js = try? Data(contentsOf: url) else {
                return http(404, "text/plain", Data("no script in the bundle".utf8))
            }
            return http(200, "text/javascript; charset=utf-8", js)
        case ("POST", "/report") where headers["x-gzyms"] == "1":
            guard let tab = try? JSONDecoder().decode(Tab.self, from: Data(body)) else { return http(400, "text/plain", Data()) }
            tabs[tab.id] = (tab, .now)
            tabs = tabs.filter { $0.value.seen > .now - 60 }
            let commands = pending.removeValue(forKey: tab.id) ?? []
            return http(200, "application/json", (try? JSONSerialization.data(withJSONObject: ["commands": commands])) ?? Data())
        default:
            return http(404, "text/plain", Data())
        }
    }

    private func http(_ code: Int, _ type: String, _ body: Data) -> Data {
        Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
    }
}

/// tools/media-reader in /usr/bin/perl (only Apple-signed processes may read MediaRemote), and media-send for commands.
@MainActor final class MediaRemoteFeed: ObservableObject {
    static let shared = MediaRemoteFeed()
    struct Now: Decodable { let app: String, appName: String, title: String, playing: Bool }
    struct Line: Decodable { let app: String, appName: String, title: String, playing: Bool; let others: [Now]? }

    @Published var now: Now?
    @Published var others: [Now] = []
    @Published var status = ""
    private var process: Process?
    private var buffer = Data()

    func start() {
        guard process == nil else { return }
        guard let reader = Bundle.main.url(forResource: "media-reader", withExtension: "dylib") else { status = "no media-reader.dylib in Probe"; return }
        let p = perl(reader), out = Pipe()
        p.standardOutput = out
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self.consume(d) } }
        }
        p.terminationHandler = { _ in DispatchQueue.main.async { MainActor.assumeIsolated { self.process = nil; self.status = "reader ended" } } }
        do { try p.run(); process = p } catch { status = "reader: \(error)" }
    }

    /// MediaRemote command to the Now Playing app: 0 play, 1 pause, 2 toggle, 4 next.
    func send(_ command: Int) {
        guard let sender = Bundle.main.url(forResource: "media-send", withExtension: "dylib") else { status = "no media-send.dylib in Probe"; return }
        let p = perl(sender)
        p.environment = ["MR_CMD": String(command)]
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
    }

    private func perl(_ dylib: URL) -> Process {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/perl")
        p.arguments = ["-e", "require DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error()", dylib.path]
        return p
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 10) {
            let line = buffer[..<nl]
            buffer = Data(buffer[buffer.index(after: nl)...])
            let l = try? JSONDecoder().decode(Line.self, from: line)
            now = l.map { Now(app: $0.app, appName: $0.appName, title: $0.title, playing: $0.playing) }
            others = l?.others ?? []
        }
    }
}

// MARK: - Shared

/// Newest first; `prefixes` empty = every line.
struct LogTail: View {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Gzyms/gzyms.log")
    var prefixes: [String] = []
    var contains = ""
    var count = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                Text(lines()).font(.system(size: 11).monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
        }
    }

    private func lines() -> String {
        guard let text = try? String(contentsOf: Self.url, encoding: .utf8) else { return "no log at \(Self.url.path)" }
        let c = contains.lowercased()
        let keep = text.split(separator: "\n").filter { l in
            (prefixes.isEmpty || prefixes.contains { l.contains($0) }) && (c.isEmpty || l.lowercased().contains(c))
        }
        return keep.suffix(count).reversed().joined(separator: "\n")
    }
}

struct Output: View {
    let text: String
    var body: some View {
        Text(text.isEmpty ? " " : text).font(.system(size: 11).monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
    }
}

enum Gzyms {
    static let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/gzyms").path
    static let tuios = "/opt/homebrew/bin/tuios"

    /// Like `run`, but `show` hears only a failure, with what the command said: "" while all goes well.
    static func runQuietly(_ args: [String], show: @escaping (String) -> Void) {
        show("")
        run(args) { text in if text.hasSuffix(")"), text.contains("(exit ") { show(text) } }
    }

    /// Runs ~/.local/bin/gzyms (or `exe`); `show` gets the command line, then its output.
    static func run(_ args: [String], exe: String = path, quiet: Bool = false, show: @escaping (String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        if quiet { p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice }
        else { p.standardOutput = pipe; p.standardError = pipe }
        let cmd = "$ \(URL(fileURLWithPath: exe).lastPathComponent) " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        show(cmd)
        do { try p.run() } catch { show(cmd + "\n\(error)"); return }
        guard !quiet else { return }
        DispatchQueue.global().async {
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            let status = p.terminationStatus
            DispatchQueue.main.async { show(cmd + "\n" + text.trimmingCharacters(in: .whitespacesAndNewlines) + (status == 0 ? "" : "  (exit \(status))")) }
        }
    }
}
