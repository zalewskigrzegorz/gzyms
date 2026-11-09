import Foundation
import TOMLDecoder

/// Everything the user sets in `~/.config/gzyms/config.toml`.
public struct GzymsConfig: Equatable, Sendable {
    public var workspaces: [WorkspaceStyle]
    public var showEmpty: Bool
    public var smallOnNotch: Bool
    /// `[workspaces] source`: HyprMac, AeroSpace or macOS Spaces. Auto takes what runs.
    public var workspaceSource = WorkspaceSource.auto
    public var theme: Theme
    public var cpuChart: CPUChart
    public var notificationSounds: Bool
    public var levelSeconds = NotifyLevel.defaultSeconds
    public var appRules: [String: AppRule] = [:]
    /// `[notifications.phone]`: where a notification left alone goes, and after how long.
    public var phone = PhonePush()
    /// `[sounds]`: per event "gzyms", a macOS sound name or a file path. Missing = the event's default.
    public var sounds: [SoundEvent: String] = [:]
    /// `[keys.verbs]`: the banner's letters (formerly `[notifications.letters]`).
    public var verbs = Verbs()
    /// Held with the pointer on the bar, it steps aside for the macOS menu bar (`[bar] menu_bar_key`).
    public var menuBarKey = MenuBarKey.cmd
    /// An image file shown on the bar instead of the cat (`[bar] logo`); nil = the cat.
    public var logo: String?
    /// `[bar] start_at_login`: a login item for a release build. The dev install has launchd's `dev.gzyms` instead.
    public var startAtLogin = true
    /// `[caffeine] display`: keep the screen on too, not only the Mac awake.
    public var caffeineDisplay = false
    /// `[caffeine] battery_below`: on battery under this %, let the Mac sleep again (0 = never).
    public var caffeineBatteryBelow = 0
    /// `[dnd] breaks_through`: what still shows during Do Not Disturb. Turning it on and off is the pill's, not the config's.
    public var dndBreaks = DNDBreak.defaults
    /// `[notifications] priority`: what sounds at once even while it waits for room in the stack.
    public var priority = DNDBreak.priorityDefaults
    /// `[notifications] open_original` (experimental): opening another app's notification presses its original in
    /// Notification Center, so the app opens the exact chat or thread. Off: just the app.
    public var openOriginal = true
    /// `[notifications] banner_ax` (experimental): reads another app's macOS banner through Accessibility the moment
    /// it shows, and parks the real one off screen. Off: the text comes from the database a few seconds later.
    public var bannerAX = true
    /// `[notifications] signal`: the app's icon shows the instant macOS logs a delivery, before the text.
    /// Off: the banner waits for its text.
    public var signal = true
    /// `[notifications] nc_auto_restart`: restarts a hung Notification Center by itself (`killall NotificationCenter`),
    /// at most once per 10 minutes. Off: only the Restart button in Settings → Hacks does it.
    public var ncAutoRestart = false
    /// `[hacks] browser_media`: the loopback server for the browser userscript, so tabs with video show in the music
    /// pill. Off until turned on in Settings → Hacks: it opens a port on 127.0.0.1.
    public var browserMedia = false
    /// `[updates] automatic`: only what the user chose against the default (`automaticUpdates`). nil: the default.
    public var updatesAutomatic: Bool?
    public var anomalies = true
    /// Global, in every app (`[shortcuts] mic_mute`, "off" = none).
    public var micShortcut = Shortcut("ctrl+alt+m")
    /// The keyboard mode (`[keys]`): its leader ("off" = none, `gzyms keys on` still works), how long it waits for a
    /// key before it ends itself (0 = never) and the letters its hints use.
    public var leader = Leader("ctrl+alt+g")
    public var idleTimeout = 30.0
    public var hintChars = KeyNav.defaultHintChars
    /// Meeting reminders (`[calendar]`): on/off and the points, minutes before the start (negative = after).
    public var calendarEnabled = true
    /// Built-in widgets turned off in Settings → Plugins (`[widgets] cpu = false`): gone from the bar, not sampled.
    public var hiddenWidgets: Set<BarWidget> = []
    /// `[widgets] left` and `order` (the right side), as written; `barLayout` turns them into the plan.
    public var layoutLeft: [String]?
    public var layoutRight: [String]?
    /// Plugin folders with `[plugins.<folder>] enabled = false`: never started.
    public var disabledPlugins: Set<String> = []
    /// What `[plugins.<folder>]` sets for the options a plugin declares (`enabled` is not among them).
    public var pluginOptions: [String: [String: TOMLValue]] = [:]
    /// When the one meeting reminder comes; snooze walks `MeetingClock.ladder` from there.
    public var meetingPoints = [3]
    /// Calendars left out, as `CalendarInfo.key`.
    public var calendarSkip: Set<String> = []
    /// Open = the check before the meeting (camera, mic, speakers), then Join; off = straight to the link.
    public var meetingPreview = true
    /// `[agents]`: each source's switch, the shortest run that notifies when it ends (minutes), the app tuios runs in.
    public var agentsTuios = true
    public var agentsClaude = true
    public var agentsDoneAfter = 3
    public var agentsTerminal = "Ghostty"
    public var animations = true
    public var followReduceMotion = true
    /// `[appearance] banner_entry`: how a banner arrives on an empty island.
    public var bannerEntry = BannerEntry.drop  // icon first delays the text by ~1 s, so it is opt-in (Greg)
    /// `[appearance] animation_speed`: scales every island and icon-flight duration.
    public var animationSpeed = AnimationSpeed.normal
    /// Whether anything moves: off with `animations = false`, and under macOS Reduce motion unless told to ignore it.
    public func animates(reduceMotion: Bool) -> Bool { animations && !(followReduceMotion && reduceMotion) }
    /// How a banner arrives (Greg's order): nil = at once with animations off, a fade under Reduce motion, else the chosen style.
    public func entry(reduceMotion: Bool) -> BannerEntry? {
        guard animations else { return nil }
        return followReduceMotion && reduceMotion ? .fade : bannerEntry
    }
    /// `[appearance] favorite_themes`: the themes the user starred in Settings → Themes, first in the list.
    public var favoriteThemes: [String] = []
    /// Device name → the icon its pills show, for hardware that reports an odd transport.
    public var deviceIcons: [String: AudioDevice.Kind] = [:]
    /// `[audio] banned`: device names M and S in the meeting preview skip, the popups dim (an iPhone mic that pops up).
    public var bannedDevices: Set<String> = []
    /// A banned iPhone mic or speaker bans its Continuity camera too: one phone, one ban (Greg, 2026-11-01).
    /// shortcut: by the word "iPhone" in the name, like `AudioDevice.kind`; match the phone by its model ID if two iPhones ever show up.
    public var bansIPhone: Bool { bannedDevices.contains { $0.localizedCaseInsensitiveContains("iphone") } }

    public static let defaults = GzymsConfig(workspaces: WorkspaceStyle.gregDefaults, showEmpty: false, smallOnNotch: false,
                                             theme: .mochaNeon, cpuChart: .line, notificationSounds: true)
}

/// Strongest first, the order Settings lists them in (Greg, after the HTML prototype of 2026-11-05).
public enum BannerEntry: String, CaseIterable, Sendable {
    /// icon: the icon drops in, then the text unrolls out of it. drop: slides down from under the edge with a spring.
    /// notch: grows out of the notch's shape. unroll: unrolls down from the edge. pop: grows from 85 % and fades in.
    /// fade: fades in where it stands, also what Reduce motion gets.
    case icon, drop, notch, unroll, pop, fade
}

public enum AnimationSpeed: String, CaseIterable, Sendable {
    case slow, normal, fast
    /// Multiplies the island's base durations. Normal is 1.5: Greg found the old slow the right pace (2026-11-05).
    public var factor: Double {
        switch self {
        case .slow: 2.25
        case .normal: 1.5
        case .fast: 0.9
        }
    }
}

public enum MenuBarKey: String, CaseIterable, Sendable {
    case cmd, ctrl, alt, shift, off
    public var name: String {
        switch self {
        case .cmd: "⌘ Cmd"
        case .ctrl: "⌃ Ctrl"
        case .alt: "⌥ Option"
        case .shift: "⇧ Shift"
        case .off: "Off"
        }
    }
}

public enum BarWidget: String, CaseIterable, Sendable {
    case music, cpu, memory, network, audio, mic, camera, shelf, dnd, caffeine, battery, clock
    public var title: String {
        switch self {
        case .camera: "Camera in use"
        case .dnd: "Do Not Disturb"
        case .shelf: "File shelf"
        case .music: "Music"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .audio: "Sound output"
        case .mic: "Microphone"
        case .caffeine: "Caffeine"
        case .battery: "Battery"
        case .clock: "Clock"
        }
    }
}

/// A place on the bar: a built-in pill, or all the pills of one plugin. Written as "cpu" or "plugin:<folder>".
public enum BarSlot: Hashable, Sendable {
    case widget(BarWidget), plugin(String)
    public init?(_ s: String) {
        if s.hasPrefix("plugin:") {
            let f = String(s.dropFirst(7))
            guard !f.isEmpty else { return nil }
            self = .plugin(f)
        } else if let w = BarWidget(rawValue: s) {
            self = .widget(w)
        } else { return nil }
    }
    public var name: String {
        switch self {
        case .widget(let w): w.rawValue
        case .plugin(let f): "plugin:\(f)"
        }
    }
}

/// Left and right of the notch (one bar without a notch: left after the workspaces, right before the clock).
public struct BarLayoutPlan: Equatable, Sendable {
    public var left: [BarSlot], right: [BarSlot]
    public init(left: [BarSlot], right: [BarSlot]) { self.left = left; self.right = right }

    /// The recommended layout: plugins on the left (the side with room on a laptop), built-ins on the right.
    public static func recommended(plugins: [String]) -> BarLayoutPlan {
        BarLayoutPlan(left: plugins.sorted().map(BarSlot.plugin), right: BarWidget.allCases.map(BarSlot.widget))
    }
}

/// The user's `[widgets] left` and `order` (the right side), each slot once. Anything they leave out takes its
/// recommended side, at the end; plugins named there but not installed are left out (their place is remembered).
public func barLayout(left: [String]?, right: [String]?, plugins: [String]) -> BarLayoutPlan {
    var seen = Set<BarSlot>()
    func take(_ names: [String]?) -> [BarSlot] { (names ?? []).compactMap(BarSlot.init).filter { seen.insert($0).inserted } }
    var l = take(left), r = take(right)
    r += BarWidget.allCases.map(BarSlot.widget).filter { seen.insert($0).inserted }
    l += plugins.sorted().map(BarSlot.plugin).filter { seen.insert($0).inserted }
    let installed = Set(plugins)
    func keep(_ s: BarSlot) -> Bool { if case .plugin(let f) = s { installed.contains(f) } else { true } }
    return BarLayoutPlan(left: l.filter(keep), right: r.filter(keep))
}

public struct ConfigLoad: Equatable, Sendable {
    public var config: GzymsConfig
    /// Human-readable, one per broken or unknown key. Never fatal.
    public var problems: [String]
    /// The file did not parse at all: the settings panel must not write over it.
    public var broken = false
}

/// A broken key keeps its default and is reported; a broken file gives the defaults and one problem.
public func loadConfig(toml: String?) -> ConfigLoad {
    guard let toml else { return ConfigLoad(config: .defaults, problems: []) }
    let data = Data(toml.utf8)
    let raw: RawConfig
    do { raw = try TOMLDecoder().decode(RawConfig.self, from: data) } catch {
        return ConfigLoad(config: .defaults, problems: ["config.toml could not be read: \(error)"], broken: true)
    }
    var config = GzymsConfig.defaults
    var problems = raw.unknown
    if let name = raw.theme {
        if let t = Theme.named(name) { config.theme = t }
        else { problems.append("theme: \"\(name)\" is not a theme (gzyms theme --list shows all \(Theme.all.count)), kept \(config.theme.name)") }
    }
    if let chart = raw.cpu?.chart {
        if let c = CPUChart(rawValue: chart) { config.cpuChart = c }
        else { problems.append("cpu.chart: \"\(chart)\" must be line or bars, kept line") }
    }
    if let v = raw.notifications?.sounds { config.notificationSounds = v }
    for (name, choice) in raw.sounds ?? [:] {
        if let e = SoundEvent(rawValue: name) { config.sounds[e] = choice }
        else { problems.append("sounds.\(name): not an event (\(SoundEvent.allCases.map(\.rawValue).joined(separator: ", "))), ignored") }
    }
    if let v = raw.debug?.anomalies { config.anomalies = v }
    if let v = raw.calendar?.enabled { config.calendarEnabled = v }
    if let v = raw.calendar?.preview { config.meetingPreview = v }
    for (folder, values) in raw.plugins ?? [:] {
        if values["enabled"] == .bool(false) { config.disabledPlugins.insert(folder) }
        let options = values.filter { $0.key != "enabled" }
        if !options.isEmpty { config.pluginOptions[folder] = options }
    }
    for (key, names) in [("left", raw.widgets?.left), ("order", raw.widgets?.order)] {
        guard let names else { continue }
        let unknown = names.filter { BarSlot($0) == nil }
        if !unknown.isEmpty { problems.append("widgets.\(key): \(unknown.joined(separator: ", ")) is not a widget or plugin:<folder>, left out") }
    }
    config.layoutLeft = raw.widgets?.left
    config.layoutRight = raw.widgets?.order
    for (name, on) in raw.widgets?.values ?? [:] {
        if let w = BarWidget(rawValue: name) { if !on { config.hiddenWidgets.insert(w) } }
        else { problems.append("widgets.\(name): not a widget (\(BarWidget.allCases.map(\.rawValue).joined(separator: ", "))), ignored") }
    }
    if let p = raw.calendar?.points {
        if !p.isEmpty, p.allSatisfy([5, 3, 0, -3].contains) { config.meetingPoints = Array(Set(p)).sorted(by: >) }
        else { problems.append("calendar.points: \(p) must be some of 5, 3, 0, -3, kept 3") }
    }
    if let s = raw.calendar?.skip { config.calendarSkip = Set(s) }
    if let v = raw.agents?.tuios { config.agentsTuios = v }
    if let v = raw.agents?.claude { config.agentsClaude = v }
    if let v = raw.agents?.done_after { config.agentsDoneAfter = max(0, v) }
    if let v = raw.agents?.terminal, !v.isEmpty { config.agentsTerminal = v }
    // Before [keys]: the hint letters leave the verbs out.
    if let v = raw.keys?.verbs.flatMap({ parseVerbs($0, path: "keys.verbs", &problems) }) { config.verbs = v }
    else if raw.keys?.verbs == nil, let v = raw.notifications?.letters.flatMap({ parseVerbs($0, path: "notifications.letters", &problems) }) {
        config.verbs = v
    }
    if raw.keys?.leader == nil, let h = raw.notifications?.hold, let l = Leader(h), l.isOldHoldKey { config.leader = l }
    if let p = oldKeysProblem(raw) { problems.append(p) }
    if let k = raw.keys {
        if let l = k.leader {
            if l == "off" { config.leader = nil }
            else if let parsed = Leader(l) { config.leader = parsed }
            else { problems.append("keys.leader: \"\(l)\" must be an F key (f19), a chord like ctrl+alt+g, ctrl, alt, cmd, or off, kept ctrl+alt+g") }
        }
        if let t = k.idle_timeout {
            if t >= 0 { config.idleTimeout = t } else { problems.append("keys.idle_timeout: \(t) must be 0 (never) or more seconds, kept 30") }
        }
        if let h = k.hint_chars {
            var seen = Set<Character>()
            let letters = h.lowercased().filter { $0.isLetter && $0.isASCII && seen.insert($0).inserted }
            let kept = KeyNav.hintChars(letters, verbs: config.verbs)
            let verbs = KeyNav.fixedVerbs + config.verbs.all.map(\.letter).joined()
            if kept.count < 2 {
                problems.append("keys.hint_chars: \"\(h)\" leaves fewer than 2 letters that are not verbs (\(verbs)), kept \(KeyNav.defaultHintChars)")
            } else {
                if kept.count < letters.count { problems.append("keys.hint_chars: \(verbs) are verbs and never hints, left out") }
                config.hintChars = kept
            }
        }
    }
    if let m = raw.shortcuts?.mic_mute {
        if m == "off" { config.micShortcut = nil }
        else if let s = Shortcut(m) { config.micShortcut = s }
        else { problems.append("shortcuts.mic_mute: \"\(m)\" must be like ctrl+alt+m (a letter or digit and ctrl, alt or cmd), or off, kept ctrl+alt+m") }
    }
    if let l = raw.bar?.logo, !l.isEmpty { config.logo = l }
    if let v = raw.bar?.start_at_login { config.startAtLogin = v }
    if let v = raw.caffeine?.display { config.caffeineDisplay = v }
    if let v = raw.caffeine?.battery_below { config.caffeineBatteryBelow = max(0, min(100, v)) }
    if let names = raw.dnd?.breaks_through {
        let bad = names.filter { DNDBreak(rawValue: $0) == nil }
        if bad.isEmpty { config.dndBreaks = Set(names.compactMap(DNDBreak.init(rawValue:))) }
        else { problems.append("dnd.breaks_through: \(bad.joined(separator: ", ")) must be \(DNDBreak.allCases.map(\.rawValue).joined(separator: ", ")), kept armageddon and meetings") }
    }
    if let v = raw.notifications?.openOriginal { config.openOriginal = v }
    if let v = raw.notifications?.bannerAX { config.bannerAX = v }
    if let v = raw.notifications?.signal { config.signal = v }
    if let v = raw.notifications?.ncAutoRestart { config.ncAutoRestart = v }
    if let v = raw.hacks?.browser_media { config.browserMedia = v }
    if let v = raw.updates?.automatic { config.updatesAutomatic = v }
    if let names = raw.notifications?.priority {
        let bad = names.filter { DNDBreak(rawValue: $0) == nil }
        if bad.isEmpty { config.priority = Set(names.compactMap(DNDBreak.init(rawValue:))) }
        else { problems.append("notifications.priority: \(bad.joined(separator: ", ")) must be \(DNDBreak.allCases.map(\.rawValue).joined(separator: ", ")), kept armageddon and critical") }
    }
    if let k = raw.bar?.menu_bar_key {
        if let m = MenuBarKey(rawValue: k) { config.menuBarKey = m }
        else { problems.append("bar.menu_bar_key: \"\(k)\" must be \(MenuBarKey.allCases.map(\.rawValue).joined(separator: ", ")), kept cmd") }
    }
    for (name, value) in raw.notifications?.levels?.values ?? [:] {
        let path = "notifications.levels.\(name)"
        switch NotifyLevel(rawValue: name) {
        case .armageddon?: problems.append("\(path): an armageddon always stays until clicked, ignored")
        case let level? where value >= 0: config.levelSeconds[level] = value == 0 ? .some(nil) : value
        case let level?: problems.append("\(path): \(value) must be 0 or more, kept \(level.seconds.map { "\(Int($0))" } ?? "0")")
        case nil: problems.append("\(path): unknown key, ignored")
        }
    }
    for (app, r) in raw.notifications?.apps?.rules ?? [:] {
        var rule = AppRule()
        if let v = r.banner { rule.banner = v }
        if let v = r.sound { rule.sound = v }
        if let v = r.count { rule.count = v }
        if let v = r.phone { rule.phone = v }
        if let v = r.skip { rule.skip = v }
        if let l = r.level {
            if let level = AppLevel(rawValue: l) { rule.level = level }
            else { problems.append("notifications.apps.\"\(app)\".level: \"\(l)\" must be normal, critical or armageddon, kept normal") }
        }
        problems += r.problems.map { "notifications.apps.\"\(app)\".\($0)" }
        config.appRules[app] = rule
    }
    if let ph = raw.notifications?.phone {
        // Secrets come from the Keychain (`withPhoneSecrets`); one left in the file is ignored and reported.
        let left = [(PhoneSecret.url, ph.url), (.pushover_user, ph.pushover_user), (.pushover_token, ph.pushover_token)]
            .filter { $0.1?.isEmpty == false }.map(\.0)
        if !left.isEmpty { problems.append(PhoneSecret.inFileProblem(left)) }
        if let f = ph.format {
            if let v = PushFormat(rawValue: f) { config.phone.format = v } else { problems.append("notifications.phone.format: \"\(f)\" must be ntfy, json or pushover, kept ntfy") }
        }
        if let m = ph.after {
            if m >= 0 { config.phone.after = m * 60 } else { problems.append("notifications.phone.after: \(m) must be 0 or more minutes, kept 5") }
        }
        if let names = ph.levels {
            let bad = names.filter { NotifyLevel(rawValue: $0) == nil }
            if bad.isEmpty { config.phone.levels = Set(names.compactMap(NotifyLevel.init(rawValue:))) }
            else { problems.append("notifications.phone.levels: \(bad.joined(separator: ", ")) is not a level (\(NotifyLevel.allCases.map(\.rawValue).joined(separator: ", "))), kept critical and armageddon") }
        }
    }
    if let v = raw.appearance?.animations { config.animations = v }
    if let v = raw.appearance?.follow_reduce_motion { config.followReduceMotion = v }
    if let s = raw.appearance?.banner_entry {
        if let v = BannerEntry(rawValue: s) { config.bannerEntry = v }
        else { problems.append("appearance.banner_entry: \"\(s)\" must be icon, drop, notch, unroll, pop or fade, kept drop") }
    }
    if let s = raw.appearance?.animation_speed {
        if let v = AnimationSpeed(rawValue: s) { config.animationSpeed = v }
        else { problems.append("appearance.animation_speed: \"\(s)\" must be slow, normal or fast, kept normal") }
    }
    if let v = raw.appearance?.favorite_themes {
        // A favourite that is not a theme any more (renamed, dropped for contrast) just leaves the list.
        config.favoriteThemes = v.filter { Theme.named($0) != nil }
    }
    if let b = raw.audio?.banned { config.bannedDevices = Set(b) }
    for (device, icon) in raw.audio?.icons ?? [:] {
        if let k = AudioDevice.Kind(rawValue: icon) { config.deviceIcons[device] = k }
        else { problems.append("audio.icons.\"\(device)\": \"\(icon)\" must be \(AudioDevice.Kind.allCases.map(\.rawValue).joined(separator: ", ")), ignored") }
    }
    if let v = raw.workspaces?.show_empty { config.showEmpty = v }
    if let v = raw.workspaces?.small_on_notch { config.smallOnNotch = v }
    if let v = raw.workspaces?.source {
        if let s = WorkspaceSource(rawValue: v) { config.workspaceSource = s }
        else { problems.append("workspaces.source: \"\(v)\" must be \(WorkspaceSource.allCases.map(\.rawValue).joined(separator: ", ")), kept auto") }
    }
    for style in raw.workspaces?.style ?? [] {
        guard let n = style.number, let i = config.workspaces.firstIndex(where: { $0.number == n }) else {
            problems.append("workspaces.style: number must be 1 to 10, got \(style.number.map(String.init) ?? "nothing")")
            continue
        }
        if let name = style.name { config.workspaces[i].name = name }
        if let color = style.color {
            // Token names resolve the same way in every theme, so checking one is enough.
            if Theme.mochaNeon.resolve(color) != nil { config.workspaces[i].color = color.hasPrefix("#") ? color.uppercased() : color }
            else { problems.append("workspaces.style[\(n)].color: \"\(color)\" is not a #RRGGBB colour or a theme colour name, kept the default") }
        }
    }
    return ConfigLoad(config: config, problems: problems)
}

/// Seven different letters a to z; h j k l f move and show hints whatever the verbs say.
private func parseVerbs(_ l: RawLetters, path: String, _ problems: inout [String]) -> Verbs? {
    let v = Verbs(open: l.open ?? "o", dismiss: l.dismiss ?? "x", alt: l.alt ?? "a", snooze: l.snooze ?? "z",
                  next: l.next ?? "n", prev: l.prev ?? "p", clear: l.clear ?? "d")
    let used = v.all.map(\.letter)
    if !used.allSatisfy({ $0.count == 1 && ("a"..."z").contains($0) && !KeyNav.fixedVerbs.contains($0) }) {
        problems.append("\(path): each must be one letter a to z, not h j k l f, kept o x z a n p d")
        return nil
    }
    if Set(used).count < used.count {
        problems.append("\(path): two actions share a letter (\(used.joined(separator: " "))), kept o x z a n p d")
        return nil
    }
    return v
}

/// `[notifications] hold`, `keys` and `[notifications.letters]` from before the leader (stage 3): still read when the
/// new keys are missing, never written over (config.toml may live in dotfiles), and reported once with what to paste.
private func oldKeysProblem(_ raw: RawConfig) -> String? {
    guard let n = raw.notifications else { return nil }
    var old: [String] = [], paste: [String] = []
    if let h = n.hold {
        old.append("notifications.hold")
        if raw.keys?.leader == nil, let l = Leader(h), l.isOldHoldKey { paste.append("[keys] leader = \"\(l.text)\"") }
    }
    if n.keys != nil { old.append("notifications.keys") }
    if let l = n.letters {
        old.append("notifications.letters")
        let set = [("open", l.open), ("dismiss", l.dismiss), ("snooze", l.snooze), ("alt", l.alt), ("next", l.next), ("prev", l.prev)]
            .compactMap { k, v in v.map { "\(k) = \"\($0)\"" } }
        if raw.keys?.verbs == nil, !set.isEmpty { paste.append("[keys.verbs] " + set.joined(separator: ", ")) }
    }
    guard !old.isEmpty else { return nil }
    return "\(old.joined(separator: ", ")): old keys, still read. The banner now follows the leader, tapped or held. "
        + (paste.isEmpty ? "Delete them." : "Delete them and write instead: \(paste.joined(separator: " · "))")
}

// MARK: - Raw TOML shape (every field optional, unknown keys collected)

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func unknownKeys(in decoder: Decoder, known: Set<String>, prefix: String) throws -> [String] {
    try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        .filter { !known.contains($0) }.sorted().map { "\(prefix)\($0): unknown key, ignored" }
}

/// One key: absent → nil; present but the wrong type → nil plus a problem. Never throws, so one bad
/// value cannot take the rest of the file down with it.
private func lenient<T: Decodable, K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K, _ path: String,
                                                 _ problems: inout [String]) -> T? {
    guard c.contains(key) else { return nil }
    guard let v = try? c.decode(T.self, forKey: key) else {
        problems.append("\(path): wrong type, kept the default")
        return nil
    }
    return v
}

private struct RawConfig: Decodable {
    var theme: String?
    var cpu: RawCPU?
    var workspaces: RawWorkspaces?
    var notifications: RawNotifications?
    var appearance: RawAppearance?
    var audio: RawAudio?
    var bar: RawBar?
    var debug: RawDebug?
    var shortcuts: RawShortcuts?
    var keys: RawKeys?
    var calendar: RawCalendar?
    var agents: RawAgents?
    var widgets: RawWidgets?
    var plugins: [String: [String: TOMLValue]]?
    var caffeine: RawCaffeine?
    var dnd: RawDND?
    var hacks: RawHacks?
    var updates: RawUpdates?
    var sounds: [String: String]?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case theme, cpu, workspaces, notifications, appearance, audio, bar, debug, shortcuts, keys, calendar, agents, widgets, plugins, caffeine, dnd, hacks, updates, sounds }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = lenient(c, .theme, "theme", &unknown)
        cpu = lenient(c, .cpu, "cpu", &unknown)
        workspaces = lenient(c, .workspaces, "workspaces", &unknown)
        notifications = lenient(c, .notifications, "notifications", &unknown)
        appearance = lenient(c, .appearance, "appearance", &unknown)
        audio = lenient(c, .audio, "audio", &unknown)
        bar = lenient(c, .bar, "bar", &unknown)
        debug = lenient(c, .debug, "debug", &unknown)
        shortcuts = lenient(c, .shortcuts, "shortcuts", &unknown)
        keys = lenient(c, .keys, "keys", &unknown)
        calendar = lenient(c, .calendar, "calendar", &unknown)
        agents = lenient(c, .agents, "agents", &unknown)
        widgets = lenient(c, .widgets, "widgets", &unknown)
        plugins = lenient(c, .plugins, "plugins", &unknown)
        caffeine = lenient(c, .caffeine, "caffeine", &unknown)
        dnd = lenient(c, .dnd, "dnd", &unknown)
        hacks = lenient(c, .hacks, "hacks", &unknown)
        updates = lenient(c, .updates, "updates", &unknown)
        sounds = lenient(c, .sounds, "sounds", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["theme", "cpu", "workspaces", "notifications", "appearance", "audio", "bar", "debug",
                                                        "shortcuts", "keys", "calendar", "agents", "widgets", "plugins", "caffeine", "dnd", "hacks", "updates", "sounds"], prefix: "")
        unknown += (calendar?.unknown ?? []) + (agents?.unknown ?? []) + (widgets?.unknown ?? [])
        unknown += (appearance?.unknown ?? []) + (audio?.unknown ?? []) + (bar?.unknown ?? []) + (debug?.unknown ?? [])
        unknown += shortcuts?.unknown ?? []
        unknown += keys?.unknown ?? []
        unknown += notifications?.unknown ?? []
        unknown += cpu?.unknown ?? []
        unknown += workspaces?.unknown ?? []
    }
}

private struct RawCPU: Decodable {
    var chart: String?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case chart }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chart = lenient(c, .chart, "cpu.chart", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["chart"], prefix: "cpu.")
    }
}

private struct RawNotifications: Decodable {
    var sounds: Bool?
    var keys: String?
    var hold: String?
    var levels: RawLevels?
    var apps: RawApps?
    var letters: RawLetters?
    var phone: RawPhone?
    var priority: [String]?
    var openOriginal: Bool?
    var bannerAX: Bool?
    var signal: Bool?
    var ncAutoRestart: Bool?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey {
        case sounds, keys, hold, levels, apps, letters, phone, priority, signal
        case openOriginal = "open_original", bannerAX = "banner_ax", ncAutoRestart = "nc_auto_restart"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sounds = lenient(c, .sounds, "notifications.sounds", &unknown)
        keys = lenient(c, .keys, "notifications.keys", &unknown)
        hold = lenient(c, .hold, "notifications.hold", &unknown)
        levels = lenient(c, .levels, "notifications.levels", &unknown)
        apps = lenient(c, .apps, "notifications.apps", &unknown)
        letters = lenient(c, .letters, "notifications.letters", &unknown)
        phone = lenient(c, .phone, "notifications.phone", &unknown)
        priority = lenient(c, .priority, "notifications.priority", &unknown)
        openOriginal = lenient(c, .openOriginal, "notifications.open_original", &unknown)
        bannerAX = lenient(c, .bannerAX, "notifications.banner_ax", &unknown)
        signal = lenient(c, .signal, "notifications.signal", &unknown)
        ncAutoRestart = lenient(c, .ncAutoRestart, "notifications.nc_auto_restart", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["sounds", "keys", "hold", "levels", "apps", "letters", "phone", "priority",
                                                        "open_original", "banner_ax", "signal", "nc_auto_restart"], prefix: "notifications.")
        unknown += (levels?.unknown ?? []) + (apps?.unknown ?? []) + (letters?.unknown ?? []) + (phone?.unknown ?? [])
    }
}

/// Seconds per level; TOML may write them as integers or decimals.
private struct RawLevels: Decodable {
    var values: [String: Double] = [:]
    var unknown: [String] = []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for k in c.allKeys {
            if let i = try? c.decode(Int.self, forKey: k) { values[k.stringValue] = Double(i) }
            else if let d = try? c.decode(Double.self, forKey: k) { values[k.stringValue] = d }
            else { unknown.append("notifications.levels.\(k.stringValue): wrong type, kept the default") }
        }
    }
}

/// `[notifications.apps."<bundle id>"]`: the table keys are bundle ids, so they are read as they come.
private struct RawApps: Decodable {
    var rules: [String: RawAppRule] = [:]
    var unknown: [String] = []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for k in c.allKeys {
            if let r = try? c.decode(RawAppRule.self, forKey: k) { rules[k.stringValue] = r }
            else { unknown.append("notifications.apps.\"\(k.stringValue)\": must be a table, ignored") }
        }
    }
}

private struct RawPhone: Decodable {
    var url: String?
    /// Minutes; TOML may write them as integers or decimals.
    var after: Double?
    var levels: [String]?
    var format: String?
    var pushover_user: String?, pushover_token: String?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case url, after, levels, format, pushover_user, pushover_token }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = lenient(c, .url, "notifications.phone.url", &unknown)
        if let i = try? c.decode(Int.self, forKey: .after) { after = Double(i) } else { after = lenient(c, .after, "notifications.phone.after", &unknown) }
        levels = lenient(c, .levels, "notifications.phone.levels", &unknown)
        format = lenient(c, .format, "notifications.phone.format", &unknown)
        pushover_user = lenient(c, .pushover_user, "notifications.phone.pushover_user", &unknown)
        pushover_token = lenient(c, .pushover_token, "notifications.phone.pushover_token", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["url", "after", "levels", "format", "pushover_user", "pushover_token"],
                                   prefix: "notifications.phone.")
    }
}

private struct RawAppRule: Decodable {
    var banner: Bool?, sound: Bool?, count: Bool?, phone: Bool?, skip: Bool?
    var level: String?
    /// Paths relative to the app's table; the loader puts `notifications.apps."<id>".` in front.
    var problems: [String] = []
    enum CodingKeys: String, CodingKey { case banner, sound, count, level, phone, skip }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        banner = lenient(c, .banner, "banner", &problems)
        sound = lenient(c, .sound, "sound", &problems)
        count = lenient(c, .count, "count", &problems)
        level = lenient(c, .level, "level", &problems)
        phone = lenient(c, .phone, "phone", &problems)
        skip = lenient(c, .skip, "skip", &problems)
        problems += try unknownKeys(in: decoder, known: ["banner", "sound", "count", "level", "phone", "skip"], prefix: "")
    }
}

private struct RawLetters: Decodable {
    var open: String?, dismiss: String?, snooze: String?, alt: String?, next: String?, prev: String?, clear: String?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case open, dismiss, snooze, alt, next, prev, clear }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `[keys.verbs]` or the old `[notifications.letters]`: the same keys.
        let p = decoder.codingPath.map(\.stringValue).joined(separator: ".") + "."
        open = lenient(c, .open, p + "open", &unknown)
        dismiss = lenient(c, .dismiss, p + "dismiss", &unknown)
        snooze = lenient(c, .snooze, p + "snooze", &unknown)
        alt = lenient(c, .alt, p + "alt", &unknown)
        next = lenient(c, .next, p + "next", &unknown)
        prev = lenient(c, .prev, p + "prev", &unknown)
        clear = lenient(c, .clear, p + "clear", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["open", "dismiss", "snooze", "alt", "next", "prev", "clear"], prefix: p)
    }
}

private struct RawAppearance: Decodable {
    var animations: Bool?, follow_reduce_motion: Bool?, banner_entry: String?, animation_speed: String?, favorite_themes: [String]?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case animations, follow_reduce_motion, banner_entry, animation_speed, favorite_themes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animations = lenient(c, .animations, "appearance.animations", &unknown)
        follow_reduce_motion = lenient(c, .follow_reduce_motion, "appearance.follow_reduce_motion", &unknown)
        banner_entry = lenient(c, .banner_entry, "appearance.banner_entry", &unknown)
        animation_speed = lenient(c, .animation_speed, "appearance.animation_speed", &unknown)
        favorite_themes = lenient(c, .favorite_themes, "appearance.favorite_themes", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["animations", "follow_reduce_motion", "banner_entry", "animation_speed", "favorite_themes"],
                                   prefix: "appearance.")
    }
}

private struct RawWidgets: Decodable {
    var values: [String: Bool] = [:]
    var order: [String]?
    var left: [String]?
    var unknown: [String] = []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for k in c.allKeys {
            if k.stringValue == "order" || k.stringValue == "left" {
                let names = try? c.decode([String].self, forKey: k)
                if names == nil { unknown.append("widgets.\(k.stringValue): must be a list of names, kept the recommended layout") }
                if k.stringValue == "order" { order = names } else { left = names }
            } else if let v = try? c.decode(Bool.self, forKey: k) { values[k.stringValue] = v }
            else { unknown.append("widgets.\(k.stringValue): wrong type, kept on") }
        }
    }
}

private struct RawCalendar: Decodable {
    var enabled: Bool?
    var preview: Bool?
    var points: [Int]?
    var skip: [String]?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case enabled, preview, points, skip }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = lenient(c, .enabled, "calendar.enabled", &unknown)
        preview = lenient(c, .preview, "calendar.preview", &unknown)
        points = lenient(c, .points, "calendar.points", &unknown)
        skip = lenient(c, .skip, "calendar.skip", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["enabled", "preview", "points", "skip"], prefix: "calendar.")
    }
}

private struct RawShortcuts: Decodable {
    var mic_mute: String?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case mic_mute }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mic_mute = lenient(c, .mic_mute, "shortcuts.mic_mute", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["mic_mute"], prefix: "shortcuts.")
    }
}

private struct RawKeys: Decodable {
    var leader: String?
    var idle_timeout: Double?
    var hint_chars: String?
    var verbs: RawLetters?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case leader, idle_timeout, hint_chars, verbs }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leader = lenient(c, .leader, "keys.leader", &unknown)
        // TOML says 30, not 30.0: an integer is a number of seconds too.
        if let i = try? c.decode(Int.self, forKey: .idle_timeout) { idle_timeout = Double(i) }
        else { idle_timeout = lenient(c, .idle_timeout, "keys.idle_timeout", &unknown) }
        hint_chars = lenient(c, .hint_chars, "keys.hint_chars", &unknown)
        verbs = lenient(c, .verbs, "keys.verbs", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["leader", "idle_timeout", "hint_chars", "verbs"], prefix: "keys.")
        unknown += verbs?.unknown ?? []
    }
}

private struct RawDebug: Decodable {
    var anomalies: Bool?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case anomalies }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anomalies = lenient(c, .anomalies, "debug.anomalies", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["anomalies"], prefix: "debug.")
    }
}

private struct RawHacks: Decodable {
    var browser_media: Bool?
}

private struct RawUpdates: Decodable {
    var automatic: Bool?
}

private struct RawAgents: Decodable {
    var tuios: Bool?
    var claude: Bool?
    var done_after: Int?
    var terminal: String?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case tuios, claude, done_after, terminal }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tuios = lenient(c, .tuios, "agents.tuios", &unknown)
        claude = lenient(c, .claude, "agents.claude", &unknown)
        done_after = lenient(c, .done_after, "agents.done_after", &unknown)
        terminal = lenient(c, .terminal, "agents.terminal", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["tuios", "claude", "done_after", "terminal"], prefix: "agents.")
    }
}

private struct RawCaffeine: Decodable {
    var display: Bool?
    var battery_below: Int?
}

private struct RawDND: Decodable {
    var breaks_through: [String]?
}

private struct RawBar: Decodable {
    var menu_bar_key: String?
    var logo: String?
    var start_at_login: Bool?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case menu_bar_key, logo, start_at_login }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menu_bar_key = lenient(c, .menu_bar_key, "bar.menu_bar_key", &unknown)
        logo = lenient(c, .logo, "bar.logo", &unknown)
        start_at_login = lenient(c, .start_at_login, "bar.start_at_login", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["menu_bar_key", "logo", "start_at_login"], prefix: "bar.")
    }
}

private struct RawAudio: Decodable {
    var icons: [String: String]?
    var banned: [String]?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case icons, banned }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icons = lenient(c, .icons, "audio.icons", &unknown)
        banned = lenient(c, .banned, "audio.banned", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["icons", "banned"], prefix: "audio.")
    }
}

private struct RawWorkspaces: Decodable {
    var show_empty: Bool?
    var small_on_notch: Bool?
    var source: String?
    var style: [RawStyle]?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case show_empty, small_on_notch, source, style }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        show_empty = lenient(c, .show_empty, "workspaces.show_empty", &unknown)
        small_on_notch = lenient(c, .small_on_notch, "workspaces.small_on_notch", &unknown)
        source = lenient(c, .source, "workspaces.source", &unknown)
        style = lenient(c, .style, "workspaces.style", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["show_empty", "small_on_notch", "source", "style"], prefix: "workspaces.")
        unknown += style?.flatMap(\.unknown) ?? []
    }
}

private struct RawStyle: Decodable {
    var number: Int?
    var name: String?
    var color: String?
    var unknown: [String] = []
    enum CodingKeys: String, CodingKey { case number, name, color }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = lenient(c, .number, "workspaces.style.number", &unknown)
        let path = "workspaces.style[\(number.map(String.init) ?? "?")]"
        name = lenient(c, .name, "\(path).name", &unknown)
        color = lenient(c, .color, "\(path).color", &unknown)
        unknown += try unknownKeys(in: decoder, known: ["number", "name", "color"], prefix: "\(path).")
    }
}
