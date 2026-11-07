import AppKit
import GzymsCore
import GzymsUI
import Observation
import SwiftUI

/// What every panel draws from. One instance for the whole app.
@Observable @MainActor
final class BarModel {
    var state: HyprMacState?
    var stale = false
    var config = GzymsConfig.defaults
    /// `config.animations`, and off while macOS "Reduce motion" is on unless the config says to ignore it.
    var animate = true
    var cpu: Double?
    var cpuSeries: [Double] = []
    var topProcesses: [ProcessCPU] = []
    var memory: MemorySample?
    var net: NetSample?
    var netDown: [Double] = []
    var netUp: [Double] = []
    var battery: BatterySample?
    var batteryWarning: BatteryWarning?
    var audio: AudioState?
    @ObservationIgnored var onAudioChange: () -> Void = {}
    @ObservationIgnored var onTestSound: () -> Void = {}
    var micLevel = 0.0
    @ObservationIgnored var onMicMute: () -> Void = {}
    @ObservationIgnored var onMicPopup: (Bool) -> Void = { _ in }
    @ObservationIgnored var onCPUPopup: (Bool) -> Void = { _ in }
    var inboxes: [String?: [GzymsNotification]] = [:]
    var dockBadges: [String: String] = [:]
    @ObservationIgnored var onOpenNote: (String) -> Void = { _ in }
    @ObservationIgnored var onRemoveNote: (String) -> Void = { _ in }
    @ObservationIgnored var onAltNote: (String) -> Void = { _ in }
    @ObservationIgnored var onLogo: () -> Void = {}
    // Settings panel
    var settingsTab = SettingsTab.general { didSet { onSettingsTab() } }
    @ObservationIgnored var onSettingsTab: () -> Void = {}
    var configProblems: [String] = []
    var configBroken = false
    /// A Homebrew install's daily look at the appcast found this newer version (Settings → About).
    var newVersion: String?
    var seenApps: [SeenApp] = []
    /// Settings → Apps, step by step: the apps to set up in macOS, and which one is open now. nil = not running.
    var appSetup: (queue: [String], at: Int)?
    var grants: [GrantState] = []
    /// Every calendar macOS knows, for the Calendar tab (filled once the calendar plugin has read).
    var calendars: [CalendarInfo] = []
    /// `[bar] logo` read once per config load, not on every redraw.
    var customLogo: NSImage?
    var nowPlaying: NowPlaying?
    /// Browser tabs with media, from the userscript through `MediaServer`.
    var tabs: [BrowserTab] = []
    @ObservationIgnored var onMusic: (MusicAction) -> Void = { _ in }
    var pluginPills: [PluginPill] = []
    var caffeine: CaffeineState?
    @ObservationIgnored var onCaffeine: (Int??) -> Void = { _ in }
    var dnd: Date?
    @ObservationIgnored var onDND: (Date?) -> Void = { _ in }
    var shelf: [URL] = []
    @ObservationIgnored var onShelf: (ShelfChange) -> Void = { _ in }
    var plugins: [PluginStatus] = []
    /// Settings → Agents: each source's live state in a few words.
    var agentSources: [AgentSource: AgentSourceStatus] = [:]
    /// The keyboard mode's hints, on the one panel it runs on; nil = off.
    var nav: NavShown?

    /// Where every pill goes: the user's `[widgets] left` / `order` plus whatever they did not place.
    var barLayout: BarLayoutPlan {
        GzymsCore.barLayout(left: config.layoutLeft, right: config.layoutRight, plugins: plugins.map(\.folder))
    }
    @ObservationIgnored var onPluginEvent: (String, PluginEvent, String) -> Void = { _, _, _ in }
    /// The settings panel is on screen and not covered by other windows (it is only ordered out when closed, never torn down).
    var settingsVisible = false { didSet { onSettingsVisible() } }
    @ObservationIgnored var onSettingsVisible: () -> Void = {}
    /// A grant that was on went off: a quiet ⚠ on the bar opens the wizard.
    var grantWarning = false
    /// `IsSecureEventInputEnabled()`: the keyboard mode cannot hear the leader.
    var secureInput = false
    /// "standup 3m" from the first point until joined, dismissed or 10 min after the start.
    var meetingPill: String?
    @ObservationIgnored var onMeetingPill: () -> Void = {}
    @ObservationIgnored var onGrantWarning: () -> Void = {}

    var audioDevices: [String] {
        var seen = Set<String>()
        return ((audio?.outputs ?? []) + (audio?.inputs ?? [])).map(\.name).filter { seen.insert($0).inserted }
    }

    /// HyprMac gone for a while (or never there): the bar shows one desktop (Greg, 2026-10-31).
    var noWindowManager = false
    var runningApps: [String] = []

    /// Where the workspaces come from now: `config.workspaceSource`, with auto resolved to what runs.
    var source = WorkspaceSource.hyprmac
    /// AeroSpace's or the Spaces' workspaces; nil = not running or not readable.
    var sourceState: HyprMacState?
    @ObservationIgnored var onSelectWorkspace: (Int) -> Void = { _ in }

    /// The live state of the source in use; nil = none (HyprMac's last file while it is gone does not count).
    var activeState: HyprMacState? { source == .hyprmac ? (stale ? nil : state) : sourceState }

    var workspaces: [BarWorkspace] {
        if source == .hyprmac {
            if noWindowManager { return singleDesktop(styles: config.workspaces, apps: runningApps) }
            return state.map { barWorkspaces(state: $0, styles: config.workspaces, showEmpty: config.showEmpty) } ?? []
        }
        guard let sourceState else { return singleDesktop(styles: config.workspaces, apps: runningApps) }
        return barWorkspaces(state: sourceState, styles: config.workspaces, showEmpty: config.showEmpty)
    }

    func apply(_ read: StateRead) {
        switch read {
        case .fresh(let s): state = s; stale = false
        case .stale(let s, _): state = s; stale = true
        case .none: state = nil; stale = false
        }
    }
}

struct NavShown: Equatable {
    var panel: ObjectIdentifier
    var labels: [HintLabel]
    var typed: String
}

/// One panel's content: the model plus this screen's notch, with a live clock.
struct PanelRoot: View {
    let model: BarModel
    let notch: NotchGap?
    var popups = PopupState()
    var panel: ObjectIdentifier?
    var popupMaxHeight: CGFloat = 600
    var onHint: (String, HintSpot?) -> Void = { _, _ in }
    var onIconFrame: (String, CGRect) -> Void = { _, _ in }

    var body: some View {
        TimelineView(.everyMinute) { context in
            BarView(workspaces: model.workspaces, small: model.config.smallOnNotch && notch != nil, notch: notch,
                    stale: model.source == .hyprmac && model.stale && !model.noWindowManager, now: context.date, cpu: model.cpu, cpuSeries: model.cpuSeries,
                    cpuChart: model.config.cpuChart, topProcesses: model.topProcesses, memory: model.memory,
                    net: model.net, netDown: model.netDown, netUp: model.netUp,
                    battery: model.battery, batteryWarning: model.batteryWarning,
                    audio: model.audio, onAudioChange: model.onAudioChange, onTestSound: { model.onTestSound() },
                    micLevel: model.micLevel, onMicMute: model.onMicMute, onMicPopup: model.onMicPopup,
                    icon: AppIcons.icon(for:), onSelect: { model.source == .hyprmac ? switchWorkspace($0) : model.onSelectWorkspace($0) }, onCPUPopup: model.onCPUPopup,
                    // Read when called: the left side sits in an equatable Redraw that keeps its first closures, and a bar drawn
                    // before the app delegate set them stayed dead (the logo did nothing for a whole session).
                    inboxes: model.inboxes, onOpenNote: { model.onOpenNote($0) }, onRemoveNote: { model.onRemoveNote($0) },
                    onLogo: { model.onLogo() }, grantWarning: model.grantWarning, onGrantWarning: model.onGrantWarning, secureInput: model.secureInput,
                    meetingPill: model.meetingPill, onMeetingPill: model.onMeetingPill, logo: model.customLogo,
                    media: mediaItems(model.nowPlaying, tabs: model.tabs, now: context.date.timeIntervalSince1970), onMusic: model.onMusic,
                    pluginPills: model.pluginPills, onPluginEvent: model.onPluginEvent,
                    caffeine: model.caffeine, onCaffeine: model.onCaffeine, dnd: model.dnd, onDND: model.onDND, shelf: model.shelf, onShelf: model.onShelf)
        }
        .environment(\.onAltNote) { model.onAltNote($0) }
        .overlay { if let nav = model.nav, nav.panel == panel { HintOverlay(labels: nav.labels, typed: nav.typed) } }
        .themed(model.config.theme)
        .environment(\.reportIconFrame, onIconFrame)
        .environment(\.popups, popups)
        .environment(\.popupMaxHeight, popupMaxHeight)
        .environment(\.clearVerb, model.config.verbs.clear)
        .environment(\.reportHint, onHint)
        .environment(\.dockBadges, model.dockBadges)
        .environment(\.animate, model.animate)
        .environment(\.hiddenCounts, Set(model.config.appRules.filter { !$0.value.count }.keys))
        .environment(\.hiddenWidgets, model.config.hiddenWidgets)
        .environment(\.barLayout, model.barLayout)
    }

    private func switchWorkspace(_ n: Int) {
        // Release and Debug both claim hyprmac://; a bare open launched the idle Debug next to the running release.
        let ids: Set<String> = ["com.zachgray.HyprMac", "com.zachgray.HyprMac.debug"]
        guard let url = URL(string: "hyprmac://workspace?n=\(n)"),
              let app = NSWorkspace.shared.runningApplications.first(where: { ids.contains($0.bundleIdentifier ?? "") })?.bundleURL
        else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
    }
}

/// App icons by bundle id, looked up once each.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    private static var ids: [String: String] = [:]

    /// Notification Center keeps bundle ids in lower case; the bar and HyprMac use the app's own spelling.
    static func bundleID(matching id: String) -> String {
        if let hit = ids[id] { return hit }
        let real = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap { Bundle(url: $0)?.bundleIdentifier } ?? id
        ids[id] = real
        return real
    }
    static func icon(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}
