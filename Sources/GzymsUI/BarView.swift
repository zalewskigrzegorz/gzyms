import AppKit
import GzymsCore
import SwiftUI

/// The notch, in bar coordinates. Content never goes there.
public struct NotchGap: Equatable, Sendable {
    public var minX: Double
    public var maxX: Double
    public init(minX: Double, maxX: Double) { self.minX = minX; self.maxX = maxX }

    /// From the widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, so it does not matter
    /// where the screen sits in global coordinates.
    public init(screenWidth: Double, leftAreaWidth: Double, rightAreaWidth: Double) {
        self.init(minX: leftAreaWidth, maxX: screenWidth - rightAreaWidth)
    }
}

/// Draws `content` again only when `key` changes. SwiftUI cannot compare closures, so a pill that takes one (a tap,
/// a popup) ran its body on every bar tick (CPU and network move every 2 s), even with its own data unchanged.
/// The environment (theme, popups closing) still reaches it as usual. Use with `.equatable()`.
struct Redraw<each Key: Equatable, Content: View>: View, @MainActor Equatable {
    let key: (repeat each Key)
    let content: () -> Content
    init(_ key: repeat each Key, @ViewBuilder content: @escaping () -> Content) {
        self.key = (repeat each key); self.content = content
    }
    static func == (a: Self, b: Self) -> Bool {
        for (l, r) in repeat (each a.key, each b.key) { if l != r { return false } }
        return true
    }
    var body: some View { content() }
}

public enum BarLayout {
    public static let notchMargin: Double = 8
    public static let horizontalPadding: Double = 10
    /// macOS draws its privacy dot (mic, camera) in the top-right corner, above every window: keep the clock clear of it.
    public static let privacyDotGap: Double = 14
    /// Width the left side may use so it stops short of the notch; nil = no limit.
    /// The left stack starts after the bar's padding, so that comes off too.
    public static func leftWidth(total: Double, notch: NotchGap?) -> Double? {
        notch.map { $0.minX - notchMargin - horizontalPadding }
    }

    /// The same for the right side, from the notch's right edge to the bar's end.
    public static func rightWidth(total: Double, notch: NotchGap?) -> Double? {
        notch.map { total - $0.maxX - notchMargin - horizontalPadding }
    }
}

extension Color {
    /// Only for hexes that come from a `Theme`; views never pass a literal.
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x808080
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension EnvironmentValues {
    @Entry public var theme: Theme = .mochaNeon
    /// Where each app icon (and "bell") sits in its panel, so a banner can fly into it.
    /// Dock badge labels by bundle id ("3", "•"): the app's own unread count wins over Gzyms' inbox count.
    @Entry public var dockBadges: [String: String] = [:]
    @Entry public var reportIconFrame: (String, CGRect) -> Void = { _, _ in }
    /// "Now" for the "2h ago" labels; nil = the real clock. Tests pin it, so a picture never depends on the day it runs.
    @Entry public var fixedNow: Date?
    /// Finder's icon for a path. Tests swap in a fixed one, so a picture never depends on what this Mac has installed.
    @Entry public var fileIcon: (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }
    /// Off with `[appearance] animations = false` or macOS "Reduce motion": counts change without the bump.
    @Entry public var animate = true
    /// Apps set to `count = false`: their icon shows no number, their list still opens.
    @Entry public var hiddenCounts: Set<String> = []
    /// Built-in widgets turned off in Settings → Plugins.
    @Entry public var hiddenWidgets: Set<BarWidget> = []
    @Entry public var barLayout = BarLayoutPlan.recommended(plugins: [])
}

extension Theme {
    /// `theme[\.sky]`
    subscript(_ token: KeyPath<Theme, String>) -> Color { Color(hex: self[keyPath: token]) }
    /// A workspace colour: a token name or a hex; anything else draws as `overlay`.
    func color(_ tokenOrHex: String) -> Color { Color(hex: resolve(tokenOrHex) ?? overlay) }
}

public struct BarView: View {
    let workspaces: [BarWorkspace]
    let small: Bool
    let notch: NotchGap?
    let stale: Bool
    let now: Date
    let cpu: Double?
    let cpuSeries: [Double]
    let cpuChart: CPUChart
    let topProcesses: [ProcessCPU]
    let memory: MemorySample?
    let net: NetSample?
    let netDown: [Double], netUp: [Double]
    let battery: BatterySample?
    let batteryWarning: BatteryWarning?
    let audio: AudioState?
    var onAudioChange: () -> Void = {}
    /// Plays Gzyms' own message sound, the one the user picked (Greg: not a macOS system sound).
    var onTestSound: () -> Void = {}
    let micLevel: Double
    var onMicMute: () -> Void = {}
    var onMicPopup: (Bool) -> Void = { _ in }
    let icon: (String) -> NSImage?
    var onSelect: (Int) -> Void = { _ in }
    var onCPUPopup: (Bool) -> Void = { _ in }
    let inboxes: [String?: [GzymsNotification]]
    var onOpenNote: (String) -> Void = { _ in }
    var onRemoveNote: (String) -> Void = { _ in }
    var onLogo: () -> Void = {}
    let grantWarning: Bool
    var onGrantWarning: () -> Void = {}
    /// macOS Secure Input is on: no key reaches the tap, so the leader does nothing.
    let secureInput: Bool
    let meetingPill: String?
    var onMeetingPill: () -> Void = {}
    /// The user's own logo (`[bar] logo`); nil = the cat.
    let logo: NSImage?
    /// What plays: `mediaItems` of Now Playing and the browser tabs; empty = no pill.
    let media: [MediaItem]
    var onMusic: (MusicAction) -> Void = { _ in }
    let pluginPills: [PluginPill]
    let caffeine: CaffeineState?
    /// .some(minutes) starts (nil minutes = until turned off), nil stops.
    var onCaffeine: (Int??) -> Void = { _ in }
    /// Do Not Disturb until then (`.distantFuture` = until turned off); nil = off.
    let dnd: Date?
    /// .some(date) turns it on until then, nil turns it off.
    var onDND: (Date?) -> Void = { _ in }
    let shelf: [URL]
    var onShelf: (ShelfChange) -> Void = { _ in }
    /// The cameras running in any app; empty = no camera pill.
    let cameras: [String]
    /// Files are being dragged over the bar: the shelf shows, even empty, to say it takes them.
    @State private var dropping = false
    var onPluginEvent: (String, PluginEvent, String) -> Void = { _, _, _ in }
    @Environment(\.theme) private var theme
    @Environment(\.hiddenWidgets) private var hidden
    @Environment(\.barLayout) private var layout

    /// Whether a slot has anything to draw right now: hidden built-ins, a silent music pill or a plugin without
    /// pills take no room (and no gap).
    private func visible(_ s: BarSlot) -> Bool {
        switch s {
        case .widget(let w): !hidden.contains(w) && (w != .music || !media.isEmpty)
            && (w != .shelf || dropping || !shelf.isEmpty) && (w != .camera || !cameras.isEmpty)
        case .plugin(let f): pluginPills.contains { $0.plugin == f }
        }
    }

    @ViewBuilder private func slot(_ s: BarSlot) -> some View {
        switch s {
        case .widget(let w): widget(w).hintTarget(w == .clock || w == .camera ? nil : "widget:\(w.rawValue)", popup: true)
        case .plugin(let f):
            let pills = pluginPills.filter { $0.plugin == f }
            // An agent's row carries its notification, so Agents gets no pile of them on top.
            let notes = f == agentsPill ? [] : pluginInbox(inboxes, plugin: f)
            Redraw(pills, notes, small) {
                HStack(spacing: small ? 4 : 6) {
                    ForEach(pills, id: \.key) { p in
                        // The plugin's notifications sit on its first pill, not in the bell.
                        let own = p.key == pills.first?.key ? notes : []
                        PluginPillView(pill: p, small: small, notes: own, onOpen: onOpenNote, onRemove: onRemoveNote) { e, id in onPluginEvent(p.plugin, e, id) }
                            .hintTarget("plugin:\(p.plugin):\(p.item.id)", popup: p.item.menu != nil || !own.isEmpty) { onPluginEvent(p.plugin, .click, p.item.id) }
                    }
                }
            }.equatable()
        }
    }

    @ViewBuilder private func widget(_ w: BarWidget) -> some View {
        switch w {
        // CPU and network change on every tick anyway; the rest redraw only when their own data moves.
        case .music:
            if !media.isEmpty {
                Redraw(media, small) { MusicView(items: media, small: small, icon: icon, onCommand: onMusic) }.equatable()
            }
        case .cpu: CPUView(percent: cpu, series: cpuSeries, chart: cpuChart, small: small, top: topProcesses, onPopup: onCPUPopup)
        case .memory: Redraw(memory, small) { MemoryView(memory: memory, small: small) }.equatable()
        case .network: NetworkView(net: net, down: netDown, up: netUp, small: small)
        case .audio: Redraw(audio, small) { AudioOutputView(audio: audio, small: small, onChange: onAudioChange, onTest: onTestSound) }.equatable()
        case .mic:
            Redraw(audio, micLevel, small) {
                AudioInputView(audio: audio, small: small, level: micLevel, onChange: onAudioChange, onMute: onMicMute, onPopup: onMicPopup)
            }.equatable()
        case .camera:
            if let help = cameraHelp(cameras) {
                // Green like macOS' own camera dot.
                Image(systemName: "video.fill")
                    .font(.system(size: small ? 10 : 12))
                    .foregroundStyle(theme[\.green])
                    .help(help)
            }
        case .battery: Redraw(battery, batteryWarning, small) { BatteryView(battery: battery, warning: batteryWarning, small: small) }.equatable()
        case .clock: Redraw(now, small) { ClockView(now: now, small: small) }.equatable()
        case .dnd: Redraw(dnd, now, small) { DNDView(until: dnd, now: now, small: small, onCommand: onDND) }.equatable()
        case .caffeine: Redraw(caffeine, now, small) { CaffeineView(state: caffeine, now: now, small: small, onCommand: onCaffeine) }.equatable()
        case .shelf: Redraw(shelf, dropping, small) { ShelfView(files: shelf, small: small, dropping: dropping, onChange: onShelf) }.equatable()
        }
    }

    public init(workspaces: [BarWorkspace], small: Bool, notch: NotchGap?, stale: Bool, now: Date,
                cpu: Double? = nil, cpuSeries: [Double] = [], cpuChart: CPUChart = .line, topProcesses: [ProcessCPU] = [],
                memory: MemorySample? = nil, net: NetSample? = nil, netDown: [Double] = [], netUp: [Double] = [],
                battery: BatterySample? = nil, batteryWarning: BatteryWarning? = nil,
                audio: AudioState? = nil, onAudioChange: @escaping () -> Void = {}, onTestSound: @escaping () -> Void = {},
                micLevel: Double = 0, onMicMute: @escaping () -> Void = {}, onMicPopup: @escaping (Bool) -> Void = { _ in },
                icon: @escaping (String) -> NSImage?, onSelect: @escaping (Int) -> Void = { _ in },
                onCPUPopup: @escaping (Bool) -> Void = { _ in },
                inboxes: [String?: [GzymsNotification]] = [:], onOpenNote: @escaping (String) -> Void = { _ in },
                onRemoveNote: @escaping (String) -> Void = { _ in }, onLogo: @escaping () -> Void = {},
                grantWarning: Bool = false, onGrantWarning: @escaping () -> Void = {}, secureInput: Bool = false,
                meetingPill: String? = nil, onMeetingPill: @escaping () -> Void = {}, logo: NSImage? = nil,
                media: [MediaItem] = [], onMusic: @escaping (MusicAction) -> Void = { _ in },
                pluginPills: [PluginPill] = [], onPluginEvent: @escaping (String, PluginEvent, String) -> Void = { _, _, _ in },
                caffeine: CaffeineState? = nil, onCaffeine: @escaping (Int??) -> Void = { _ in },
                dnd: Date? = nil, onDND: @escaping (Date?) -> Void = { _ in },
                shelf: [URL] = [], onShelf: @escaping (ShelfChange) -> Void = { _ in }, cameras: [String] = []) {
        self.shelf = shelf; self.onShelf = onShelf; self.cameras = cameras
        self.dnd = dnd; self.onDND = onDND
        self.logo = logo; self.media = media; self.onMusic = onMusic
        self.pluginPills = pluginPills; self.onPluginEvent = onPluginEvent
        self.caffeine = caffeine; self.onCaffeine = onCaffeine
        self.workspaces = workspaces; self.small = small; self.notch = notch; self.stale = stale
        self.now = now; self.cpu = cpu; self.cpuSeries = cpuSeries; self.cpuChart = cpuChart; self.topProcesses = topProcesses
        self.memory = memory; self.net = net; self.netDown = netDown; self.netUp = netUp
        self.battery = battery; self.batteryWarning = batteryWarning; self.audio = audio; self.onAudioChange = onAudioChange; self.onTestSound = onTestSound
        self.micLevel = micLevel; self.onMicMute = onMicMute; self.onMicPopup = onMicPopup
        self.icon = icon; self.onSelect = onSelect; self.onCPUPopup = onCPUPopup
        self.inboxes = inboxes; self.onOpenNote = onOpenNote; self.onRemoveNote = onRemoveNote; self.onLogo = onLogo
        self.grantWarning = grantWarning; self.onGrantWarning = onGrantWarning; self.secureInput = secureInput
        self.meetingPill = meetingPill; self.onMeetingPill = onMeetingPill
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                HStack(spacing: small ? 4 : 6) {
                // Workspaces, their app icons and the bell change seldom; the 2 s ticks on the right leave them alone.
                let pillPlugins = Set(pluginPills.map(\.plugin))
                Redraw(logo, workspaces, inboxes, pillPlugins, small) {
                HStack(spacing: small ? 4 : 6) {
                    // Gzyms' own menu (Settings, Quit), behind the logo.
                    LogoButton(logo: logo, small: small, onLogo: onLogo).hintTarget("logo", popup: false, action: onLogo)
                    ForEach(workspaces, id: \.number) { ws in
                        WorkspaceItem(ws: ws, small: small, icon: icon, inboxes: inboxes, onOpen: onOpenNote, onRemove: onRemoveNote)
                            .onTapGesture { onSelect(ws.number) }
                            // No hint: switching workspaces is HyprMac's (Greg); hints here open the apps' lists.
                    }
                    BellView(notes: bellInbox(inboxes, onBar: Set(workspaces.flatMap(\.appBundleIDs)), pills: pillPlugins), small: small,
                             onOpen: onOpenNote, onRemove: onRemoveNote)
                }
                }
                .equatable()
                // Left of the notch, in the user's layout (Settings → Plugins); plugins sit here by default.
                ForEach(layout.left.filter(visible), id: \.self) { s in slot(s) }
                }
                .fixedSize()  // items keep their size; what does not fit is clipped, never squeezed
                .opacity(stale ? 0.45 : 1)
                .frame(maxWidth: BarLayout.leftWidth(total: geo.size.width, notch: notch).map { CGFloat($0) }, alignment: .leading)
                .clipped()
                Spacer(minLength: 0)
                // The right side stops short of the notch too; the track title gives way first ("…").
                HStack(spacing: 0) {
                if let meetingPill {
                    // Click = join.
                    Label(meetingPill, systemImage: "video.fill")
                        .font(.system(size: small ? 10 : 12, weight: .semibold))
                        .foregroundStyle(theme[\.base])
                        .padding(.horizontal, small ? 6 : 8).padding(.vertical, small ? 2 : 4)
                        .background(theme[\.sky], in: RoundedRectangle(cornerRadius: 10))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onMeetingPill)
                        .hintTarget("meeting", popup: false, action: onMeetingPill)
                        .padding(.trailing, small ? 4 : 6)
                }
                if grantWarning {
                    // A permission was taken away: say so instead of quietly showing stale counts.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: small ? 10 : 12))
                        .foregroundStyle(theme[\.peach])
                        .padding(.trailing, small ? 4 : 6)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onGrantWarning)
                        .hintTarget("grant", popup: false, action: onGrantWarning)
                        .help("Gzyms lost a permission. Click to fix.")
                }
                if secureInput {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .font(.system(size: small ? 10 : 12))
                        .foregroundStyle(theme[\.peach])
                        .padding(.trailing, small ? 4 : 6)
                        .help("Secure Input is on: macOS keeps the keyboard from Gzyms, so the leader does nothing. Close the password field, or quit the app that holds it.")
                }
                // In the user's layout (Settings → Plugins); the last one sits flush against the privacy dot gap.
                let shown = layout.right.filter(visible)
                ForEach(shown, id: \.self) { s in
                    slot(s)
                        .padding(.trailing, s == shown.last ? 0 : s == .widget(.battery) ? (small ? 8 : 12) : (small ? 4 : 6))
                        .layoutPriority(s == .widget(.music) ? -1 : 0)
                }
                Spacer().frame(width: BarLayout.privacyDotGap)
                }
                .frame(maxWidth: BarLayout.rightWidth(total: geo.size.width, notch: notch).map { CGFloat($0) }, alignment: .trailing)
                .clipped()
            }
            .padding(.horizontal, BarLayout.horizontalPadding)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(theme[\.base])
            // Files dropped anywhere on the bar go to the shelf, so nobody has to aim at a small pill.
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !hidden.contains(.shelf), !files.isEmpty else { return false }
                onShelf(.add(files))
                return true
            } isTargeted: { dropping = $0 && !hidden.contains(.shelf) }
        }
    }
}

struct WorkspaceItem: View {
    let ws: BarWorkspace
    let small: Bool
    let icon: (String) -> NSImage?
    var inboxes: [String?: [GzymsNotification]] = [:]
    var onOpen: (String) -> Void = { _ in }
    var onRemove: (String) -> Void = { _ in }
    @Environment(\.theme) private var theme

    var body: some View {
        let color = theme.color(ws.color)
        let side: CGFloat = small ? 14 : 18
        HStack(spacing: small ? 3 : 5) {
            Text(ws.label)
                .font(.system(size: small ? 10 : 12, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            ForEach(ws.appBundleIDs, id: \.self) { id in
                AppIconItem(id: id, image: icon(id), side: side, notes: inboxes[id] ?? [], onOpen: onOpen, onRemove: onRemove)
            }
        }
        .padding(.horizontal, small ? 5 : 7)
        .padding(.vertical, small ? 2 : 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(ws.isActive ? color.opacity(0.22) : theme[\.surface].opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ws.isActive ? color : .clear, lineWidth: 1))
    }
}

/// An app on a workspace, with its unread count. A click with a count opens its list instead of the workspace.
struct AppIconItem: View {
    let id: String
    let image: NSImage?
    let side: CGFloat
    let notes: [GzymsNotification]
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.reportIconFrame) private var report
    @Environment(\.dockBadges) private var dockBadges
    @Environment(\.hiddenCounts) private var hiddenCounts

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: 3).fill(theme[\.overlay].opacity(0.5))
            }
        }
        .frame(width: side, height: side)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report(id, $0) }
        .overlay(alignment: .topTrailing) {
            if !hiddenCounts.contains(id), let source = CountSource(app: dockBadges[id] != nil, gzyms: !notes.isEmpty) {
                // Small, in the icon's corner: never under the workspace's frame or the next icon (Greg), 2 pt out at most.
                CountBadge(text: CountSource.text(app: dockBadges[id], gzyms: notes.count), fill: source.fill)
                    .offset(x: side < 16 ? 1 : 2, y: side < 16 ? -1 : -2)
            }
        }
        .modifier(InboxPopover(id: "app:\(id)", notes: notes, onOpen: onOpen, onRemove: onRemove))
        // Only with something in its list; otherwise the workspace's hint covers the icon.
        .hintTarget(notes.isEmpty ? nil : "app:\(id)", popup: true)
    }
}

extension View {
    /// The short grow-and-back when `trigger` changes; still with animations off. Every frame of it redraws the
    /// whole bar: keyframes stop after 0.36 s, phaseAnimator([1, s, 1]) ran 0.54 s (+70% CPU per mute, 2026-11-01).
    func bump<T: Equatable>(on trigger: T, to scale: Double = 1.12) -> some View { modifier(Bump(trigger: trigger, scale: scale)) }
}

private struct Bump<T: Equatable>: ViewModifier {
    let trigger: T
    let scale: Double
    @Environment(\.animate) private var animate
    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: animate ? trigger : nil) { v, s in v.scaleEffect(s) } keyframes: { _ in
            CubicKeyframe(scale, duration: 0.18)
            CubicKeyframe(1.0, duration: 0.18)
        }
    }
}

/// Whose count an app's icon shows, each in its own colour: the app's own Dock badge (clearing in Gzyms never zeroes
/// it, only the app does), Gzyms's list, or both. Every accent reads on `base` (ThemeTests), and the text is `base`.
enum CountSource: Equatable {
    case app, gzyms, both

    /// Both: the sum (Greg, 2026-11-04), even where the app counts the same messages. The real number, the app's and
    /// Gzyms's alike, up to "99+" (one look for all, nobody reads past it, Greg). "•" alone stays a dot, with Gzyms's count it gives that
    /// count. Another label ("1K") stays as the app wrote it.
    static func text(app: String?, gzyms: Int) -> String {
        func number(_ n: Int) -> String { n > 99 ? "99+" : "\(n)" }
        guard let app else { return number(gzyms) }
        if let n = Int(app) { return number(min(n, 100) + gzyms) }  // a huge badge must not overflow the sum
        if app == "•" { return gzyms > 0 ? number(gzyms) : app }
        return app
    }

    init?(app: Bool, gzyms: Bool) {
        switch (app, gzyms) {
        case (true, true): self = .both
        case (true, false): self = .app
        case (false, true): self = .gzyms
        case (false, false): return nil
        }
    }

    var fill: KeyPath<Theme, String> {
        switch self {
        case .app: \.red  // like the Dock's own badge
        case .gzyms: \.sky
        case .both: \.mauve
        }
    }
}

/// Small capsule with the count; bumps when the count changes. More digits, a smaller font: "99+" still leaves the
/// icon in view (Greg).
struct CountBadge: View {
    let text: String
    let fill: KeyPath<Theme, String>
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: [7, 7, 6, 5][min(text.count, 4) - 1], weight: .bold).monospacedDigit())
            .foregroundStyle(theme[\.base])
            .padding(.horizontal, 1.5)
            .frame(minWidth: 9, minHeight: 9)
            .background(Capsule().fill(theme[fill]))
            .fixedSize()
            .bump(on: text, to: 1.7)
    }
}

/// Notifications from apps without an icon on the bar and from no app at all. Hidden at zero.
public struct BellView: View {
    let notes: [GzymsNotification]
    let small: Bool
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.reportIconFrame) private var report
    @Environment(\.hiddenCounts) private var hiddenCounts
    /// Plugins with Count off still file here, they just do not add to the number.
    private var counted: Int { notes.filter { ruleKey($0).map { !hiddenCounts.contains($0) } ?? true }.count }
    public init(notes: [GzymsNotification], small: Bool, onOpen: @escaping (String) -> Void = { _ in },
                onRemove: @escaping (String) -> Void = { _ in }) {
        self.notes = notes; self.small = small; self.onOpen = onOpen; self.onRemove = onRemove
    }
    public var body: some View {
        if !notes.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "bell.fill").font(.system(size: small ? 10 : 12))
                Text(counted > 0 ? badgeText(counted) : "").font(.system(size: small ? 10 : 12, weight: .bold).monospacedDigit())
                    .frame(width: small ? 14 : 17, alignment: .leading)
            }
            .foregroundStyle(theme[\.gold])
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report("bell", $0) }
            .padding(.horizontal, small ? 5 : 7)
            .padding(.vertical, small ? 2 : 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme[\.surface].opacity(0.6)))
            .bump(on: notes.count, to: 1.25)
            .modifier(InboxPopover(id: "bell", notes: notes, onOpen: onOpen, onRemove: onRemove))
            .hintTarget("bell", popup: true)
        } else {
            // Still reports its place, so the first notification for the 🔔 has somewhere to fly.
            Color.clear.frame(width: 1, height: 1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report("bell", $0) }
        }
    }
}

/// Tap toggles the list (only with something in it); closes on the menu bar epoch and when the list empties.
struct InboxPopover: ViewModifier {
    let id: String
    let notes: [GzymsNotification]
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // Without notifications the click falls through to the workspace (on an app icon) instead.
            .gesture(TapGesture().onEnded { popups.binding(id).wrappedValue.toggle() }, including: notes.isEmpty ? .subviews : .all)
            .onChange(of: notes.isEmpty) { if notes.isEmpty, popups.open == id { popups.open = nil } }
            // dd does what Clear all does, on the list as it is now.
            .onChange(of: notes.map(\.id), initial: true) { popups.clears[id] = { [notes, onRemove] in notes.forEach { onRemove($0.id) } } }
            .onDisappear { popups.clears[id] = nil }
            .popover(isPresented: popups.binding(id), arrowEdge: .bottom) {
                InboxList(notes: notes, onOpen: { popups.open = nil; onOpen($0) }, onRemove: onRemove)
                    .environment(\.theme, theme).environment(\.popups, popups)
            }
    }
}

/// One app's (or the bell's) notifications, newest first.
public struct InboxList: View {
    let notes: [GzymsNotification]
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    @Environment(\.theme) private var theme
    public init(notes: [GzymsNotification], onOpen: @escaping (String) -> Void = { _ in }, onRemove: @escaping (String) -> Void = { _ in }) {
        self.notes = notes; self.onOpen = onOpen; self.onRemove = onRemove
    }
    public var body: some View {
        // Outside the scroll: Clear all stays reachable however long the list is.
        VStack(alignment: .leading, spacing: 2) { InboxRows(notes: notes, onOpen: onOpen, onRemove: onRemove) }
            .popupStyle(theme, width: 320) { InboxHeader(notes: notes, onRemove: onRemove) }
    }
}

/// "3 unread" and Clear all, above a list of notifications.
struct InboxHeader: View {
    let notes: [GzymsNotification]
    let onRemove: (String) -> Void
    @Environment(\.clearVerb) private var clearVerb
    @Environment(\.theme) private var theme
    var body: some View {
        HStack {
            Text("\(notes.count) unread").foregroundStyle(theme[\.overlay])
            Spacer()
            PopupRow(action: { notes.forEach { onRemove($0.id) } }) {
                Text("Clear all").foregroundStyle(theme[\.red])
                Text(clearVerb + clearVerb).foregroundStyle(theme[\.overlay])
            }
                .fixedSize()
        }
    }
}

/// The rows of a notification list, keyboard places 0 to count - 1.
struct InboxRows: View {
    let notes: [GzymsNotification]
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    @Environment(\.onAltNote) private var onAlt
    @Environment(\.theme) private var theme
    @Environment(\.fixedNow) private var fixedNow
    private static let ago: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    var body: some View {
        ForEach(Array(notes.enumerated()), id: \.element.id) { i, n in
            PopupRow(index: i, remove: { onRemove(n.id) }, alt: n.hasAlt ? { onAlt(n.id) } : nil, action: { onOpen(n.id) }) {
                if n.reminder { Image(systemName: "clock.fill").foregroundStyle(theme[\.gold]) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title).lineLimit(1)
                    if let b = n.body { Text(b).lineLimit(1).foregroundStyle(theme[\.overlay]) }
                }
                Spacer(minLength: 6)
                Group {
                    if let fixedNow { Text(Self.ago.localizedString(for: n.at, relativeTo: fixedNow)) }
                    else { Text(n.at, format: .relative(presentation: .numeric, unitsStyle: .narrow)) }  // ticks by itself
                }
                .foregroundStyle(theme[\.overlay])
                Image(systemName: "xmark").foregroundStyle(theme[\.overlay])
                    .contentShape(Rectangle())
                    .onTapGesture { onRemove(n.id) }
                    .allowsWindowActivationEvents(true)
            }
        }
    }
}

/// "CPU 12%" plus the last minute as a line (as in the prototype) or bars, in a pill.
/// Fixed width, so 3% and 100% take the same space.
public struct CPUView: View {
    let percent: Double?
    let series: [Double]
    let chart: CPUChart
    let small: Bool
    let top: [ProcessCPU]
    let onPopup: (Bool) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(percent: Double?, series: [Double], chart: CPUChart = .line, small: Bool,
                top: [ProcessCPU] = [], onPopup: @escaping (Bool) -> Void = { _ in }) {
        self.percent = percent; self.series = series; self.chart = chart; self.small = small
        self.top = top; self.onPopup = onPopup
    }

    public var body: some View {
        HStack(spacing: small ? 4 : 5) {
            Image(systemName: "cpu").help("CPU")  // an icon, not the word: the bar is tight (Greg)
            Text(percent.map { String(format: "%.0f%%", $0) } ?? "–")
                .foregroundStyle((percent ?? 0) > SystemCPU.hot ? theme[\.red] : theme[\.text])
                .lineLimit(1)
                .frame(width: small ? 26 : 30, alignment: .trailing)
            // Shapes, not a Canvas: a Canvas redrawn every 2 s held ~75 MB of GPU buffers for 10 s at a time.
            let shown = Array(series.suffix(30))
            Group {
                switch chart {
                case .line: CPUSpark(values: shown).stroke(theme[\.sky], lineWidth: 1.2)
                case .bars:
                    ZStack {
                        BarsShape(values: shown, top: 100, slots: 30, only: { $0 <= SystemCPU.hot }).fill(theme[\.green].opacity(0.8))
                        BarsShape(values: shown, top: 100, slots: 30, only: { $0 > SystemCPU.hot }).fill(theme[\.red])
                    }
                }
            }
            .frame(width: small ? 26 : 34, height: small ? 11 : 14)
        }
        .font(.system(size: small ? 10 : 11).monospacedDigit())
        .foregroundStyle(theme[\.text])
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { popups.binding("widget:cpu").wrappedValue.toggle() }
        .popover(isPresented: popups.binding("widget:cpu"), arrowEdge: .bottom) {
            TopProcessesView(top: top).environment(\.theme, theme).environment(\.popups, popups)
        }
        .onChange(of: popups.open == "widget:cpu") { _, on in onPopup(on) }
    }
}

/// The last 30 CPU samples as a line, newest on the right, 0 to 100 %.
struct CPUSpark: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let step = rect.width / 30
        var p = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.width - Double(values.count - 1 - i) * step, y: rect.height - min(v, 100) / 100 * rect.height)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// One bar per value, the last `slots` of them, newest on the right, `top` = full room. The bars stand on `base`
/// (0 = top edge, 1 = bottom edge) and grow up, or hang from it with `downward`. `only` skips bars but keeps their place.
/// Shapes rather than a Canvas: a Canvas redrawn every 2 s held ~75 MB of GPU buffers.
struct BarsShape: Shape {
    let values: [Double]
    let top: Double
    var slots = 60
    var base = 1.0
    var downward = false
    var only: (@Sendable (Double) -> Bool)?

    func path(in r: CGRect) -> Path {
        let w = r.width / Double(slots), b = r.height * base, room = downward ? r.height - b : b
        let shown = values.suffix(slots)
        var p = Path()
        for (i, v) in shown.enumerated() where only?(v) ?? true {
            let h = max(1, min(v, top) / top * room)
            p.addRect(CGRect(x: r.width - Double(shown.count - i) * w, y: downward ? b : b - h, width: max(w - 0.5, 1), height: h))
        }
        return p
    }
}

/// The CPU popup: the busiest processes in percent of one core, like Activity Monitor (the pill is the whole Mac).
public struct TopProcessesView: View {
    let top: [ProcessCPU]
    @Environment(\.theme) private var theme
    public init(top: [ProcessCPU]) { self.top = top }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top processes · % of one core").foregroundStyle(theme[\.overlay])
            if top.isEmpty { Text("measuring…").foregroundStyle(theme[\.overlay]) }
            ForEach(top, id: \.pid) { p in
                HStack {
                    Text(p.name).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Text(String(format: "%.1f%%", p.percent))
                        .foregroundStyle(p.percent > SystemCPU.hot ? theme[\.red] : theme[\.text])
                }
            }
            ActivityMonitorLink()
        }
        .popupStyle(theme)
    }
}

/// ☕ grey while off; gold with the time left while the Mac is kept awake. The popup picks how long.
public struct CaffeineView: View {
    let state: CaffeineState?
    let now: Date
    let small: Bool
    let onCommand: (Int??) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(state: CaffeineState?, now: Date, small: Bool, onCommand: @escaping (Int??) -> Void) {
        self.state = state; self.now = now; self.small = small; self.onCommand = onCommand
    }

    public var body: some View {
        HStack(spacing: small ? 3 : 4) {
            Image(systemName: state == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
            if let state { Text(state.label(now: now)).monospacedDigit() }
        }
        .font(.system(size: small ? 10 : 11))
        .foregroundStyle(state == nil ? theme[\.overlay] : theme[\.gold])
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { popups.binding("widget:caffeine").wrappedValue.toggle() }
        .help(state == nil ? "Caffeine: keep the Mac awake" : "Caffeine is on")
        .popover(isPresented: popups.binding("widget:caffeine"), arrowEdge: .bottom) {
            CaffeinePopup(state: state, now: now) { popups.open = nil; onCommand($0) }.environment(\.theme, theme).environment(\.popups, popups)
        }
    }
}

public struct CaffeinePopup: View {
    let state: CaffeineState?
    let now: Date
    let onCommand: (Int??) -> Void
    @State private var step = 7.0  // index into CaffeineState.steps: 2 h
    @Environment(\.theme) private var theme
    public init(state: CaffeineState?, now: Date, onCommand: @escaping (Int??) -> Void) { self.state = state; self.now = now; self.onCommand = onCommand }

    private static func text(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    public var body: some View {
        let minutes = CaffeineState.steps[Int(step)]
        VStack(alignment: .leading, spacing: 8) {
            Text(state.map { $0.forever ? "Awake until you turn it off" : "Awake, \($0.label(now: now)) left" } ?? "Keep the Mac awake")
                .foregroundStyle(state == nil ? theme[\.text] : theme[\.gold])
            HStack {
                Slider(value: $step, in: 0...Double(CaffeineState.steps.count - 1), step: 1)
                Text(Self.text(minutes)).frame(width: 56, alignment: .trailing)
            }
            HStack(spacing: 6) {
                ForEach(Array([30, 60, 120, 240].enumerated()), id: \.element) { i, m in
                    Button(Self.text(m)) { onCommand(.some(m)) }.navRow(i, choose: { onCommand(.some(m)) })
                }
                Button("∞") { onCommand(.some(nil)) }.help("until you turn it off").navRow(4, choose: { onCommand(.some(nil)) })
            }
            HStack {
                Button("Start \(Self.text(minutes))") { onCommand(.some(minutes)) }.keyboardShortcut(.defaultAction)
                if state != nil { Button("Turn off") { onCommand(nil) }.navRow(5, choose: { onCommand(nil) }) }
            }
        }
        .popupStyle(theme, width: 300)
    }
}

/// 🌙 grey while off; mauve with the time left during Do Not Disturb. The popup picks how long.
public struct DNDView: View {
    let until: Date?
    let now: Date
    let small: Bool
    let onCommand: (Date?) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(until: Date?, now: Date, small: Bool, onCommand: @escaping (Date?) -> Void) {
        self.until = until; self.now = now; self.small = small; self.onCommand = onCommand
    }

    public var body: some View {
        HStack(spacing: small ? 3 : 4) {
            Image(systemName: until == nil ? "moon" : "moon.fill")
            if let until { Text(CaffeineState(until: until).label(now: now)).monospacedDigit() }
        }
        .font(.system(size: small ? 10 : 11))
        .foregroundStyle(until == nil ? theme[\.overlay] : theme[\.mauve])
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { popups.binding("widget:dnd").wrappedValue.toggle() }
        .help(until == nil ? "Do Not Disturb" : "Do Not Disturb is on")
        .popover(isPresented: popups.binding("widget:dnd"), arrowEdge: .bottom) {
            DNDPopup(until: until, now: now) { popups.open = nil; onCommand($0) }.environment(\.theme, theme).environment(\.popups, popups)
        }
    }
}

public struct DNDPopup: View {
    let until: Date?
    let now: Date
    let onCommand: (Date?) -> Void
    @Environment(\.theme) private var theme
    public init(until: Date?, now: Date, onCommand: @escaping (Date?) -> Void) { self.until = until; self.now = now; self.onCommand = onCommand }

    public var body: some View {
        let choices: [(String, Date)] = [("1 h", now + 3600), ("Until tomorrow", dndUntilMorning(now: now)), ("∞", .distantFuture)]
        VStack(alignment: .leading, spacing: 8) {
            Text(until.map { $0 == .distantFuture ? "Quiet until you turn it off" : "Quiet, \(CaffeineState(until: $0).label(now: now)) left" }
                 ?? "Do Not Disturb")
                .foregroundStyle(until == nil ? theme[\.text] : theme[\.mauve])
            Text("Banners wait in their lists, the phone still gets them.").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
            HStack(spacing: 6) {
                ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                    Button(c.0) { onCommand(c.1) }.navRow(i, choose: { onCommand(c.1) })
                }
                if until != nil { Button("Turn off") { onCommand(nil) }.navRow(choices.count, choose: { onCommand(nil) }) }
            }
        }
        .popupStyle(theme, width: 300)
    }
}

/// A pill a plugin asked for: an SF Symbol and a text, in a theme colour. A pill with a `menu` opens its list
/// (and tells the plugin `open`); otherwise a click goes straight to the plugin. Right clicks always do.
public struct PluginPillView: View {
    let pill: PluginPill
    let small: Bool
    /// The plugin's own notifications: counted on the pill, listed at the top of its popup.
    let notes: [GzymsNotification]
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    let send: (PluginEvent, String) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    @Environment(\.reportIconFrame) private var report
    @Environment(\.hiddenCounts) private var hiddenCounts
    @Environment(\.timeZone) private var timeZone
    public init(pill: PluginPill, small: Bool, notes: [GzymsNotification] = [], onOpen: @escaping (String) -> Void = { _ in },
                onRemove: @escaping (String) -> Void = { _ in }, send: @escaping (PluginEvent, String) -> Void) {
        self.pill = pill; self.small = small; self.notes = notes; self.onOpen = onOpen; self.onRemove = onRemove; self.send = send
    }
    var popupID: String { "plugin:\(pill.plugin):\(pill.item.id)" }

    public var body: some View {
        let i = pill.item, failure = pill.failure
        HStack(spacing: small ? 4 : 5) {
            if let icon = i.icon { Image(systemName: icon).font(.system(size: small ? 9 : 10)) }
            pluginText(i.text, theme).lineLimit(1).truncationMode(.tail).frame(maxWidth: small ? 110 : 160)
            if failure != nil { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: small ? 8 : 9)).foregroundStyle(theme[\.peach]) }
        }
        .font(.system(size: small ? 10 : 11))
        // A pill that cannot get its data greys out: its numbers are old and must not pass for fresh.
        .foregroundStyle(failure == nil ? theme.tint(i.color) : theme[\.overlay])
        .opacity(failure == nil ? 1 : 0.6)
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        // A banner that runs out flies here, not to the bell.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report("plugin:\(pill.plugin)", $0) }
        .overlay(alignment: .topTrailing) {
            if !notes.isEmpty, !hiddenCounts.contains("plugin:\(pill.plugin)") {
                CountBadge(text: CountSource.text(app: nil, gzyms: notes.count), fill: CountSource.gzyms.fill).offset(x: 2, y: -2)
            }
        }
        .overlay(Clicks(left: {
            guard i.menu != nil || !notes.isEmpty || failure != nil else { send(.click, i.id); return }
            popups.binding(popupID).wrappedValue.toggle()
        }, right: { send(.rightClick, i.id) }))
        .help(failure.map { "\($0.message) \(failureSince($0, timeZone))" } ?? i.tooltip ?? pill.plugin)
        // Opened by a click or by the keyboard: the plugin hears it either way.
        .onChange(of: popups.open == popupID) { _, on in if on { send(.open, i.id) } }
        // dd clears its notifications; a popup that was only them closes when they are gone.
        .onChange(of: notes.map(\.id), initial: true) {
            popups.clears[popupID] = notes.isEmpty ? nil : { [notes, onRemove] in notes.forEach { onRemove($0.id) } }
            if notes.isEmpty, i.menu == nil, failure == nil, popups.open == popupID { popups.open = nil }
        }
        .onDisappear { popups.clears[popupID] = nil }
        .popover(isPresented: popups.binding(popupID), arrowEdge: .bottom) {
            PluginMenuView(rows: i.menu ?? [], notes: notes, failure: failure, onOpen: { popups.open = nil; onOpen($0) }, onRemove: onRemove) { e, id in
                popups.open = nil; send(e, id)
            }.environment(\.theme, theme).environment(\.popups, popups)
        }
    }
}

/// "Since 19:02", in the viewer's time.
func failureSince(_ f: PluginFailure, _ tz: TimeZone) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = tz
    fmt.dateFormat = "HH:mm"
    return "Since \(fmt.string(from: f.since))."
}

/// A plugin's text with its `:symbol:` pieces drawn as SF Symbols, in the text's font and colour, or the `@colour` they name.
func pluginText(_ s: String, _ theme: Theme) -> Text {
    textPieces(s) { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }.reduce(Text(verbatim: "")) { t, p in
        switch p {
        case .text(let x): Text("\(t)\(Text(verbatim: x))")
        case .symbol(let n, let c?): Text("\(t)\(Text(Image(systemName: n)).foregroundColor(theme.tint(c)))")
        case .symbol(let n, nil): Text("\(t)\(Image(systemName: n))")
        }
    }
}

/// A plugin's list: tag, text, detail per row, the whole row clickable (left and right). The plugin's own
/// notifications come first, with their count and Clear all on top.
public struct PluginMenuView: View {
    let rows: [PluginRow]
    let notes: [GzymsNotification]
    /// Why the pill is greyed out: said first, and the rows under it are old.
    let failure: PluginFailure?
    let onOpen: (String) -> Void
    let onRemove: (String) -> Void
    let send: (PluginEvent, String) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.timeZone) private var timeZone
    public init(rows: [PluginRow], notes: [GzymsNotification] = [], failure: PluginFailure? = nil, onOpen: @escaping (String) -> Void = { _ in },
                onRemove: @escaping (String) -> Void = { _ in }, send: @escaping (PluginEvent, String) -> Void) {
        self.rows = rows; self.notes = notes; self.failure = failure; self.onOpen = onOpen; self.onRemove = onRemove; self.send = send
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let failure {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme[\.peach])
                    Text(failure.message).lineLimit(2).foregroundStyle(theme[\.text])
                    Spacer(minLength: 8)
                    Text(failureSince(failure, timeZone)).foregroundStyle(theme[\.overlay]).layoutPriority(1)
                }
                .font(.system(size: 12)).padding(.horizontal, 6).padding(.vertical, 4)
                if !rows.isEmpty || !notes.isEmpty { Divider().padding(.vertical, 3) }
            }
            if !notes.isEmpty {
                InboxRows(notes: notes, onOpen: onOpen, onRemove: onRemove)
                if !rows.isEmpty { Divider().padding(.vertical, 3) }
            }
            // Only rows with an id take the keyboard; they are numbered among themselves, after the notifications.
            let live = rows.indices.filter { rows[$0].id != nil && !rows[$0].separator }
            ForEach(Array(rows.enumerated()), id: \.offset) { n, r in
                if r.separator { Divider().padding(.vertical, 3) }
                else { PluginRowView(row: r, index: live.firstIndex(of: n).map { $0 + notes.count }, send: send) }
            }
            .opacity(failure == nil ? 1 : 0.5)
        }
        .popupStyle(theme, width: 580) { if !notes.isEmpty { InboxHeader(notes: notes, onRemove: onRemove) } }
    }
}

private struct PluginRowView: View {
    let row: PluginRow
    let index: Int?
    let send: (PluginEvent, String) -> Void
    @State private var hover = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let tag = row.tag {
                pluginText(tag, theme).font(.system(size: 11, weight: .semibold).monospaced()).foregroundStyle(theme.tint(row.color))
                    .frame(width: 82, alignment: .leading)
            }
            pluginText(row.text, theme).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(row.id == nil ? theme[\.overlay] : theme[\.text])
            Spacer(minLength: 8)
            if let d = row.detail { pluginText(d, theme).foregroundStyle(theme[\.overlay]).lineLimit(1).layoutPriority(1) }
        }
        .opacity(row.dim ? 0.5 : 1)
        .font(.system(size: 12))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover && row.id != nil ? theme[\.surface] : .clear))
        .modifier(OptionalNavRow(index: index, choose: { if let id = row.id { send(.click, id) } }, remove: nil))
        .onHover { hover = $0 }
        .overlay {
            if let id = row.id { Clicks(left: { send(.click, id) }, right: { send(.rightClick, id) }) }
        }
    }
}

/// Left and right mouse down, which SwiftUI's tap gesture cannot tell apart (it has no right click).
struct Clicks: NSViewRepresentable {
    let left: () -> Void
    let right: () -> Void
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) { v.left = left; v.right = right }
    final class V: NSView {
        var left: () -> Void = {}
        var right: () -> Void = {}
        override func mouseDown(with event: NSEvent) { left() }
        override func rightMouseDown(with event: NSEvent) { right() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

extension Theme {
    /// A plugin's colour: a token name or a hex; the text colour for anything else.
    func tint(_ name: String?) -> Color { name.flatMap { resolve($0) }.map { Color(hex: $0) } ?? Color(hex: text) }
}

/// The media pill: ▶ and the main item's "Artist – Title", then a small icon for every other source (dim = paused).
/// With less room the title shortens, then only icons stay, a waveform by each that plays. No artwork and no
/// animation: the bar stays still while music plays (Greg, 2026-11-03).
public struct MusicView: View {
    let items: [MediaItem]
    let small: Bool
    let icon: (String) -> NSImage?
    let onCommand: (MusicAction) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(items: [MediaItem], small: Bool, icon: @escaping (String) -> NSImage? = { _ in nil }, onCommand: @escaping (MusicAction) -> Void) {
        self.items = items; self.small = small; self.icon = icon; self.onCommand = onCommand
    }

    public var body: some View {
        if let main = mainMedia(items) {
            ViewThatFits(in: .horizontal) {
                full(main) { Text(main.line).lineLimit(1).truncationMode(.tail).frame(maxWidth: small ? 110 : 170, alignment: .leading) }
                full(main) { Text(main.line).lineLimit(1).truncationMode(.tail).frame(width: small ? 56 : 72, alignment: .leading) }
                compact(main)
            }
            .contentShape(Rectangle())
            .onTapGesture { popups.binding("widget:music").wrappedValue.toggle() }
            .popover(isPresented: popups.binding("widget:music"), arrowEdge: .bottom) {
                MusicDetailsView(items: items, icon: icon, onCommand: onCommand).environment(\.theme, theme).environment(\.popups, popups)
            }
        }
    }

    private func full<T: View>(_ main: MediaItem, @ViewBuilder title: () -> T) -> some View {
        let rest = items.filter { $0.id != main.id }
        return chip {
            Image(systemName: main.playing ? "play.fill" : "pause.fill").font(.system(size: small ? 8 : 9))
                .foregroundStyle(main.playing ? theme[\.green] : theme[\.overlay])
            title()
            ForEach(rest.prefix(4)) { MediaIcon(item: $0, icon: icon, size: small ? 10 : 11).opacity($0.playing ? 1 : 0.4) }
            if rest.count > 4 { Text("+\(rest.count - 4)").font(.system(size: small ? 8 : 9)).foregroundStyle(theme[\.overlay]) }
        }
    }

    /// The icons alone, for a full bar: one per playing source, or the main one with its pause.
    private func compact(_ main: MediaItem) -> some View {
        let playing = items.filter(\.playing)
        return chip {
            ForEach(playing.isEmpty ? [main] : playing) { it in
                HStack(spacing: 2) {
                    MediaIcon(item: it, icon: icon, size: small ? 11 : 13)
                    Image(systemName: it.playing ? "waveform" : "pause.fill").font(.system(size: small ? 8 : 9))
                        .foregroundStyle(it.playing ? theme[\.green] : theme[\.overlay])
                }
            }
        }
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: small ? 4 : 5) { content() }
            .font(.system(size: small ? 10 : 11))
            .foregroundStyle(theme[\.text])
            .padding(.horizontal, small ? 6 : 8)
            .padding(.vertical, small ? 2 : 4)
            .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
    }
}

/// An app's icon, or a play glyph for a browser tab (no favicons: nothing is fetched).
struct MediaIcon: View {
    let item: MediaItem
    let icon: (String) -> NSImage?
    let size: CGFloat
    @Environment(\.theme) private var theme
    var body: some View {
        if !item.isTab, let image = icon(item.app) {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: item.isTab ? "play.rectangle.fill" : "music.note").font(.system(size: size - 2))
                .foregroundStyle(theme[\.sky]).frame(width: size, height: size)
        }
    }
}

/// Every source, one row each; the row the keyboard (or a click) is on opens with its progress and ⏮ ⏯ ⏭.
/// On a row: Enter goes to it, the alt verb (a) plays or pauses and keeps the popup open, the remove verb (x) skips.
public struct MusicDetailsView: View {
    let items: [MediaItem]
    let icon: (String) -> NSImage?
    let onCommand: (MusicAction) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.popups) private var popups
    public init(items: [MediaItem], icon: @escaping (String) -> NSImage? = { _ in nil }, onCommand: @escaping (MusicAction) -> Void) {
        self.items = items; self.icon = icon; self.onCommand = onCommand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                VStack(alignment: .leading, spacing: 6) {
                    header(it)
                        .contentShape(Rectangle())
                        .onTapGesture { popups.row = i }
                        .navRow(i, choose: { onCommand(goTo(it)) }, remove: command(it, .next).map { a in { onCommand(a) } },
                                alt: command(it, .playPause).map { a in { onCommand(a) } }, altStays: true)
                    if i == open { details(it) }
                }
            }
        }
        .popupStyle(theme, width: 300)
        // The main item opens first, whichever way the popup was opened.
        .onAppear { if let m = mainMedia(items), let i = items.firstIndex(of: m) { popups.row = i } }
    }

    private var open: Int { min(popups.row, items.count - 1) }

    private func header(_ it: MediaItem) -> some View {
        HStack(spacing: 7) {
            MediaIcon(item: it, icon: icon, size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(it.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(it.artist.isEmpty ? it.from : "\(it.artist) · \(it.from)").font(.system(size: 10)).foregroundStyle(theme[\.overlay]).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: it.playing ? "play.fill" : "pause.fill").font(.system(size: 9))
                .foregroundStyle(it.playing ? theme[\.green] : theme[\.overlay])
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
    }

    @ViewBuilder private func details(_ it: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let np = it.clock, np.duration > 0 {
                // Ticks only while the popup is open.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let p = np.position(now: ctx.date.timeIntervalSince1970)
                    VStack(spacing: 2) {
                        ProgressView(value: p, total: np.duration).tint(theme[\.mauve])
                        HStack { Text(Self.clock(p)); Spacer(); Text(Self.clock(np.duration)) }
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(theme[\.overlay])
                    }
                }
                .busy("music popup progress, every 1 s")
            }
            if it.steerable {
                HStack(spacing: 18) {
                    Spacer()
                    button("backward.fill", command(it, .previous))
                    button(it.playing ? "pause.fill" : "play.fill", command(it, .playPause))
                    button("forward.fill", command(it, .next))
                    Spacer()
                }
            } else {
                Text("macOS lets Gzyms steer only the Now Playing app. Go to it to play or pause.")
                    .font(.system(size: 10)).foregroundStyle(theme[\.overlay]).fixedSize(horizontal: false, vertical: true)
            }
            Label("Go to \(it.from)", systemImage: "arrow.up.forward.app").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                .contentShape(Rectangle()).onTapGesture { onCommand(goTo(it)) }
        }
        .padding(.horizontal, 4).padding(.bottom, 6)
    }

    private func button(_ symbol: String, _ a: MusicAction?) -> some View {
        Image(systemName: symbol).font(.system(size: 15)).frame(width: 30, height: 24)
            .contentShape(Rectangle()).onTapGesture { if let a { onCommand(a) } }
    }

    /// nil for an app macOS does not let Gzyms steer.
    private func command(_ it: MediaItem, _ c: MediaCommand) -> MusicAction? {
        switch it.source {
        case .nowPlaying: .key(c)
        case .app: MediaItem.scriptable.contains(it.app) ? .script(app: it.app, c) : nil
        case .tab(let id, let i): .tab(id, media: i, c == .playPause ? .toggle : c == .next ? .next : .previous)
        }
    }

    private func goTo(_ it: MediaItem) -> MusicAction {
        if case .tab(let id, let i) = it.source { return .tab(id, media: i, .focus) }
        return .jump(app: it.app, title: it.title)
    }

    static func clock(_ s: Double) -> String {
        let t = Int(s.rounded(.down))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// "MEM 58%", warning colour above `MemorySample.warnAbove`; the popup shows usage and swap.
public struct MemoryView: View {
    let memory: MemorySample?
    let small: Bool
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(memory: MemorySample?, small: Bool) { self.memory = memory; self.small = small }

    public var body: some View {
        let warn = memory?.warn == true
        HStack(spacing: small ? 4 : 5) {
            Image(systemName: "memorychip").help("Memory")
            Text(memory.map { String(format: "%.0f%%", $0.percent) } ?? "–")
                .lineLimit(1)
                .frame(width: small ? 26 : 30, alignment: .trailing)
        }
        .font(.system(size: small ? 10 : 11).monospacedDigit())
        .foregroundStyle(warn ? theme[\.peach] : theme[\.text])
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(warn ? theme[\.peach] : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { popups.binding("widget:memory").wrappedValue.toggle() }
        .popover(isPresented: popups.binding("widget:memory"), arrowEdge: .bottom) {
            if let memory { MemoryDetailsView(memory: memory).environment(\.theme, theme).environment(\.popups, popups) }
        }
    }
}

public struct MemoryDetailsView: View {
    let memory: MemorySample
    @Environment(\.theme) private var theme
    public init(memory: MemorySample) { self.memory = memory }

    public var body: some View {
        let gb = { (b: UInt64) in b < 1 << 30 ? String(format: "%.0f MB", Double(b) / 1_048_576) : String(format: "%.1f GB", Double(b) / 1_073_741_824) }
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory").foregroundStyle(theme[\.overlay])
            HStack { Text("Used"); Spacer(); Text(String(format: "%.0f%% of %.0f GB", memory.percent, Double(memory.total) / 1_073_741_824)) }
                .foregroundStyle(memory.warn ? theme[\.peach] : theme[\.text])
            HStack { Text("Swap"); Spacer(); Text(gb(memory.swap)) }
            ActivityMonitorLink()
        }
        .popupStyle(theme)
    }
}

/// Wi-Fi/cable icon and live ↓/↑; a system proxy that is on gets the warning colour and ⇄.
public struct NetworkView: View {
    let net: NetSample?
    let down: [Double], up: [Double]
    let small: Bool
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(net: NetSample?, down: [Double] = [], up: [Double] = [], small: Bool) {
        self.net = net; self.down = down; self.up = up; self.small = small
    }

    public var body: some View {
        let proxy = net?.proxy != nil
        // Arrow and number are one text: a number wider than its own frame used to spill over half its arrow (Greg).
        // The pair keeps one width, so the bar does not jump.
        let num = { (arrow: String, s: String) in
            Text(arrow + "\u{2009}" + s).lineLimit(1).fixedSize().frame(width: small ? 32 : 37, alignment: .trailing)
        }
        HStack(spacing: small ? 3 : 4) {
            Image(systemName: net?.kind == .wifi ? "wifi" : net?.kind == .ethernet ? "cable.connector" : "wifi.slash")
                .frame(width: small ? 14 : 16, height: small ? 11 : 13)  // wifi and cable glyphs differ in height
            num("↓", net.map { NetSample.short($0.down) } ?? "–").foregroundStyle(theme[\.sky])
            num("↑", net.map { NetSample.short($0.up) } ?? "–").foregroundStyle(theme[\.mauve])
            // As in the SketchyBar widget: TS green (orange with an exit node), PX gold. The slot keeps its width.
            HStack(spacing: 3) {
                Text("TS").foregroundStyle(net?.tailscaleExit == true ? theme[\.peach] : theme[\.green]).opacity(net?.tailscale == nil ? 0 : 1)
                Text("PX").foregroundStyle(theme[\.gold]).opacity(proxy ? 1 : 0)
            }
            .font(.system(size: small ? 8 : 9, weight: .bold).monospaced())
        }
        .font(.system(size: small ? 10 : 11).monospacedDigit())
        .foregroundStyle(theme[\.text])
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(proxy ? theme[\.gold] : .clear, lineWidth: 1))
        // A short bump when the link, Tailscale or the proxy changes, as in the prototype.
        .bump(on: net?.state ?? "")
        .contentShape(Rectangle())
        .onTapGesture { popups.binding("widget:network").wrappedValue.toggle() }
        .popover(isPresented: popups.binding("widget:network"), arrowEdge: .bottom) {
            if let net { NetworkDetailsView(net: net, down: down, up: up).environment(\.theme, theme) }
        }
    }
}

public struct NetworkDetailsView: View {
    let net: NetSample
    let down: [Double], up: [Double]
    @Environment(\.theme) private var theme
    public init(net: NetSample, down: [Double], up: [Double]) { self.net = net; self.down = down; self.up = up }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Network").foregroundStyle(theme[\.overlay])
            HStack {
                Text(net.kind == .wifi ? "Wi-Fi" : net.kind == .ethernet ? "Ethernet" : "Offline")
                Spacer()
                Text(net.ip ?? "–")
            }
            HStack {
                Text("Now"); Spacer()
                Text("↓ " + NetSample.long(net.down)).foregroundStyle(theme[\.sky])
                Text("↑ " + NetSample.long(net.up)).foregroundStyle(theme[\.mauve])
            }
            TwoWayChart(down: down, up: up)
            HStack {
                Text("Tailscale"); Spacer()
                Text(net.tailscale.map { net.tailscaleExit ? "\($0) · exit node" : $0 } ?? "off")
                    .foregroundStyle(net.tailscale == nil ? theme[\.overlay] : net.tailscaleExit ? theme[\.peach] : theme[\.green])
            }
            HStack {
                Text("System proxy"); Spacer()
                Text(net.proxy ?? "off").foregroundStyle(net.proxy == nil ? theme[\.overlay] : theme[\.gold])
            }
        }
        .popupStyle(theme)
    }
}

/// 60 s of traffic: ↓ grows up from the middle, ↑ grows down.
struct TwoWayChart: View {
    let down: [Double], up: [Double]
    @Environment(\.theme) private var theme
    var body: some View {
        let top = max(1e6, (down + up).max() ?? 0) * 1.1
        Text("↓ \(NetSample.long(top)) · 60 s").font(.system(size: 9)).foregroundStyle(theme[\.overlay])
        ZStack {
            BarsShape(values: down, top: top, base: 0.5).fill(theme[\.sky].opacity(0.75))
            BarsShape(values: up, top: top, base: 0.5, downward: true).fill(theme[\.mauve].opacity(0.75))
        }
        .frame(height: 50)
    }
}

/// "78%" with a battery or plug icon; orange when the charger cannot keep up or the battery runs low.
public struct BatteryView: View {
    let battery: BatterySample?
    let warning: BatteryWarning?
    let small: Bool
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(battery: BatterySample?, warning: BatteryWarning?, small: Bool) {
        self.battery = battery; self.warning = warning; self.small = small
    }

    public var body: some View {
        if let b = battery {
            let warn = warning != nil
            HStack(spacing: small ? 3 : 4) {
                Image(systemName: b.plugged ? (b.charging ? "bolt.fill" : "powerplug.fill") : "battery.\([0, 25, 50, 75, 100].min { abs($0 - b.percent) < abs($1 - b.percent) } ?? 50)percent")
                    .frame(width: small ? 16 : 20, height: small ? 11 : 13)
                Text("\(b.percent)%").lineLimit(1).frame(width: small ? 30 : 36, alignment: .trailing)
                if warning == .chargerTooWeak { Text(String(format: "⚠ %.0f W", b.batteryW)) }
            }
            .font(.system(size: small ? 10 : 11).monospacedDigit())
            .foregroundStyle(warn ? theme[\.peach] : theme[\.text])
            .padding(.horizontal, small ? 6 : 8)
            .padding(.vertical, small ? 2 : 4)
            .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(warn ? theme[\.peach] : .clear, lineWidth: 1))
            .bump(on: "\(b.plugged)|\(warning.map { "\($0)" } ?? "")")
            .contentShape(Rectangle())
            .onTapGesture { popups.binding("widget:battery").wrappedValue.toggle() }
            .popover(isPresented: popups.binding("widget:battery"), arrowEdge: .bottom) { BatteryDetailsView(battery: b).environment(\.theme, theme) }
        }
    }
}

public struct BatteryDetailsView: View {
    let battery: BatterySample
    @Environment(\.theme) private var theme
    public init(battery: BatterySample) { self.battery = battery }

    public var body: some View {
        let b = battery, draining = b.draining
        VStack(alignment: .leading, spacing: 4) {
            Text("Battery").foregroundStyle(theme[\.overlay])
            HStack { Text("Charge"); Spacer(); Text("\(b.percent)%") }
            if !b.full {
                HStack {
                    Text(b.plugged ? "Full in" : "Time remaining"); Spacer()
                    Text(b.timeLeft ?? "No estimate").foregroundStyle(b.timeLeft == nil ? theme[\.overlay] : theme[\.text])
                }
            }
            HStack { Text("Power adapter"); Spacer(); Text(b.plugged ? b.adapterW.map { "\($0) W" } ?? "connected" : "not connected") }
            if let w = b.systemW { HStack { Text("Mac is using"); Spacer(); Text(String(format: "%.0f W", w)) } }
            HStack {
                Text("Battery"); Spacer()
                // "draining" (orange) only when the cable is in and the battery still drops; unplugged use is normal.
                Text(!b.plugged ? String(format: "on battery · %.0f W", -b.batteryW)
                     : draining ? String(format: "draining %.0f W", -b.batteryW)
                     : b.full ? "full" : b.batteryW > 0.5 ? String(format: "charging +%.0f W", b.batteryW) : "idle")
                    .foregroundStyle(!b.plugged ? theme[\.text] : draining ? theme[\.peach] : theme[\.green])
            }
            if b.plugged && draining, let w = b.systemW {
                Text(String(format: "The charger is too weak for what the Mac is doing. Use one of %.0f W or more, or close something heavy.", w + 10))
                    .foregroundStyle(theme[\.peach]).fixedSize(horizontal: false, vertical: true)
            }
        }
        .popupStyle(theme)
    }
}

/// Killing a process is Activity Monitor's job; the popups only open it.
struct ActivityMonitorLink: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PopupRow(index: 0, action: {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            dismiss()
        }) { Text("Open Activity Monitor…").foregroundStyle(theme[\.sky]) }
        .padding(.top, 2)
    }
}

/// A clickable popup row: hover highlight, link cursor, works on the first click.
struct PopupRow<Content: View>: View {
    /// Its place for the keyboard (j/k, Enter, x); nil = mouse only.
    var index: Int?
    var remove: (() -> Void)?
    var alt: (() -> Void)?
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme
    @State private var hover = false
    init(index: Int? = nil, remove: (() -> Void)? = nil, alt: (() -> Void)? = nil, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.index = index; self.remove = remove; self.alt = alt; self.action = action; self.content = content()
    }
    var body: some View {
        HStack { content }
            .padding(.vertical, 3).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? theme[\.overlay].opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .modifier(OptionalNavRow(index: index, choose: action, remove: remove, alt: alt))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .pointerStyle(.link)
            .onTapGesture(perform: action)
            .allowsWindowActivationEvents(true)  // the bar never activates, so without this the first click is lost
    }
}

/// 🔊/🎧 with the volume; the popup picks the output device and plays a test sound.
public struct AudioOutputView: View {
    let audio: AudioState?
    let small: Bool
    let onChange: () -> Void
    let onTest: () -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(audio: AudioState?, small: Bool, onChange: @escaping () -> Void = {}, onTest: @escaping () -> Void = {}) {
        self.audio = audio; self.small = small; self.onChange = onChange; self.onTest = onTest
    }

    public var body: some View {
        let dev = audio?.outputDevice, muted = audio?.outputMuted == true
        HStack(spacing: small ? 3 : 4) {
            Image(systemName: deviceSymbol(dev?.kind, input: false, muted: muted))
                .frame(width: small ? 14 : 18, height: small ? 11 : 13)
            Text(audio?.volume.map { String(format: "%.0f", $0 * 100) } ?? "–").lineLimit(1).frame(width: small ? 20 : 24, alignment: .trailing)
        }
        .font(.system(size: small ? 10 : 11).monospacedDigit())
        .foregroundStyle(muted ? theme[\.red] : theme[\.text])  // red like the muted mic: grey was too easy to miss
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
        .bump(on: "\(audio?.output ?? 0)|\(muted)")
        .contentShape(Rectangle())
        .onTapGesture { popups.binding("widget:audio").wrappedValue.toggle() }
        .popover(isPresented: popups.binding("widget:audio"), arrowEdge: .bottom) {
            if let audio {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output").foregroundStyle(theme[\.overlay])
                    DeviceList(devices: audio.pickable(input: false), selected: audio.output) { Audio.setDefaultAsync($0, input: false) { _ in onChange() } }
                    PopupRow(index: audio.pickable(input: false).count, action: onTest) { Text("Test sound"); Spacer(); Text("▶") }
                }
                .popupStyle(theme).environment(\.theme, theme).environment(\.popups, popups)
            }
        }
    }
}

/// 🎙, red 🎙✕ when muted; the popup picks the input device and mutes it.
public struct AudioInputView: View {
    let audio: AudioState?
    let small: Bool
    let level: Double
    let onChange: () -> Void
    let onMute: () -> Void
    let onPopup: (Bool) -> Void
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme
    public init(audio: AudioState?, small: Bool, level: Double = 0, onChange: @escaping () -> Void = {},
                onMute: @escaping () -> Void = {}, onPopup: @escaping (Bool) -> Void = { _ in }) {
        self.audio = audio; self.small = small; self.level = level; self.onChange = onChange; self.onMute = onMute; self.onPopup = onPopup
    }

    public var body: some View {
        let muted = audio?.inputMuted == true
        Image(systemName: deviceSymbol(audio?.inputDevice?.kind, input: true, muted: muted))
            .frame(width: small ? 14 : 16, height: small ? 11 : 13)
            .font(.system(size: small ? 10 : 11))
            .foregroundStyle(muted ? theme[\.red] : theme[\.text])
            .padding(.horizontal, small ? 6 : 8)
            .padding(.vertical, small ? 2 : 4)
            .background(theme[\.surface], in: RoundedRectangle(cornerRadius: 10))
            .bump(on: muted)
            .contentShape(Rectangle())
            .onTapGesture { popups.binding("widget:mic").wrappedValue.toggle() }
            .onChange(of: popups.open == "widget:mic") { _, on in onPopup(on) }
            .popover(isPresented: popups.binding("widget:mic"), arrowEdge: .bottom) {
                if let audio {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input").foregroundStyle(theme[\.overlay])
                        DeviceList(devices: audio.pickable(input: true), selected: audio.input) { Audio.setDefaultAsync($0, input: true) { _ in onChange() } }
                        HStack {
                            Text("Level")
                            Spacer()
                            // Live while the popup is open; flat when muted, which is the point of checking.
                            GeometryReader { g in
                                Capsule().fill(theme[\.overlay].opacity(0.3))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(level > 0.85 ? theme[\.red] : theme[\.green]).frame(width: g.size.width * level)
                                    }
                            }
                            .frame(width: 110, height: 6)
                            .animation(.linear(duration: 0.08), value: level)
                        }
                        .padding(.horizontal, 4)
                        if audio.input != nil {
                            PopupRow(index: audio.pickable(input: true).count, action: { onMute(); onChange() }) {
                                Text(muted ? "Unmute" : "Mute").foregroundStyle(muted ? theme[\.red] : theme[\.text])
                            }
                        }
                    }
                    .popupStyle(theme).environment(\.theme, theme).environment(\.popups, popups)
                }
            }
    }
}

struct DeviceList: View {
    let devices: [AudioDevice]
    let selected: UInt32?
    let pick: (UInt32) -> Void
    var body: some View {
        ForEach(Array(devices.enumerated()), id: \.element.id) { i, d in
            // Only the live one can be banned here (macOS picked it by itself): dimmed, with its ✓.
            PopupRow(index: i, action: { pick(d.id) }) {
                Text(d.name).lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(d.id == selected ? "✓" : "")
            }
            .opacity(d.banned ? 0.4 : 1)
            .help(d.banned ? "Banned. M and S skip it." : "")
        }
    }
}

extension View {
    /// `width` is the whole popup's, padding included: a wider one (a plugin's list) passes its own, or 220 cuts it.
    /// Taller than the screen allows (`popupMaxHeight`), the list scrolls; `header` stays above it.
    func popupStyle(_ theme: Theme, width: CGFloat = 220) -> some View { popupStyle(theme, width: width) { EmptyView() } }

    func popupStyle(_ theme: Theme, width: CGFloat = 220, @ViewBuilder header: () -> some View) -> some View {
        // Gzyms never becomes the active app, so the popover's window is not key: without this the first click only
        // activates it, and after every action (a media key, a Go to) the next click did nothing (Greg, 2026-11-02).
        modifier(PopupFrame(theme: theme, width: width, header: header())).allowsWindowActivationEvents()
    }

    /// Every window's root: the theme for Gzyms' own colours, and light or dark for what macOS draws (Greg: all of it changes).
    public func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme).preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

/// Every popup's frame: a fixed width outside the scroll (a ScrollView alone reports its narrowest width and cuts the rows),
/// the height of its content up to `popupMaxHeight`, and the keyboard's row kept in view.
private struct PopupFrame<Header: View>: ViewModifier {
    let theme: Theme
    let width: CGFloat
    let header: Header
    @Environment(\.popups) private var popups
    @Environment(\.popupMaxHeight) private var maxHeight

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: popups.row) { _, r in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(NavID(index: r)) } }
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(theme[\.text])
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(theme[\.surface])
        // The popover's own edge and arrow, and the system controls inside, follow the theme too.
        .presentationBackground(theme[\.surface])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

/// Fixed width: "09:05" and "23:59" take the same space, so nothing next to it jumps.
public struct ClockView: View {
    let now: Date
    let small: Bool
    @Environment(\.theme) private var theme
    public init(now: Date, small: Bool) { self.now = now; self.small = small }
    public var body: some View {
        Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            .font(.system(size: small ? 11 : 13, weight: .medium).monospacedDigit())
            .foregroundStyle(theme[\.text])
            .frame(width: small ? 38 : 44, alignment: .trailing)
    }
}

/// The device at a glance on the audio pills; crossed out (or the plain slashed mic / speaker) when muted.
func deviceSymbol(_ kind: AudioDevice.Kind?, input: Bool, muted: Bool) -> String {
    let plainOff = input ? "mic.slash.fill" : "speaker.slash.fill"
    let (on, off): (String, String) = switch kind {
    case .builtIn?: ("laptopcomputer", "laptopcomputer.slash")
    case .iPhone?: ("iphone", "iphone.slash")
    // headset for the mic: the output pill next to it already shows headphones. No headset.slash exists.
    case .headphones?: input ? ("headset", plainOff) : ("headphones", "headphones.slash")
    case .monitor?: ("display", plainOff)
    case .camera?: ("web.camera.fill", plainOff)
    case .mic?: ("mic.fill", "mic.slash.fill")
    case .speaker?: ("hifispeaker.fill", "speaker.slash.fill")
    case .external?, nil: input ? ("mic.fill", "mic.slash.fill") : ("speaker.wave.2.fill", "speaker.slash.fill")
    }
    return muted ? off : on
}

/// The logo (assets/AppIcon.svg, "J1": a cat on the cornice, the island under it) without its tile, in theme colours.
struct GzymsLogo: View {
    /// Seconds of an animation clock (About): the tail sways, the eyes blink, the island glows. nil = still.
    var t: Double?
    @Environment(\.theme) private var theme
    var body: some View {
        Canvas { ctx, size in
            // The SVG's drawing spans x 8…82, y 10…79 of its 90×90 box.
            let s = min(size.width / 74, size.height / 69)
            ctx.translateBy(x: (size.width - 74 * s) / 2 - 8 * s, y: (size.height - 69 * s) / 2 - 10 * s)
            ctx.scaleBy(x: s, y: s)
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
            var cornice = Path()
            cornice.move(to: p(10, 55)); cornice.addLine(to: p(80, 55)); cornice.addQuadCurve(to: p(82, 57), control: p(82, 55))
            cornice.addLine(to: p(82, 62)); cornice.addQuadCurve(to: p(80, 64), control: p(82, 64)); cornice.addLine(to: p(74, 64))
            cornice.addCurve(to: p(62, 71), control1: p(69, 64), control2: p(68, 71)); cornice.addLine(to: p(28, 71))
            cornice.addCurve(to: p(16, 64), control1: p(22, 71), control2: p(21, 64)); cornice.addLine(to: p(10, 64))
            cornice.addQuadCurve(to: p(8, 62), control: p(8, 64)); cornice.addLine(to: p(8, 57))
            cornice.addQuadCurve(to: p(10, 55), control: p(8, 55)); cornice.closeSubpath()
            ctx.fill(cornice, with: .color(theme[\.mauve]))
            let island = Path(roundedRect: CGRect(x: 30, y: 66, width: 30, height: 13), cornerRadius: 6.5)
            ctx.fill(island, with: .color(theme[\.sky].opacity(t.map { 0.75 + 0.25 * sin($0 * 2) } ?? 1)))
            ctx.stroke(island, with: .color(theme[\.base]), lineWidth: 2.5)
            var cat = Path()
            cat.move(to: p(31, 55)); cat.addCurve(to: p(45, 33), control1: p(31, 41), control2: p(35, 33))
            cat.addCurve(to: p(57, 55), control1: p(55, 33), control2: p(57, 43)); cat.closeSubpath()
            cat.addEllipse(in: CGRect(x: 35, y: 16, width: 20, height: 20))
            cat.move(to: p(36, 22)); cat.addLine(to: p(37, 10)); cat.addLine(to: p(44, 17)); cat.closeSubpath()
            cat.move(to: p(46, 17)); cat.addLine(to: p(53, 10)); cat.addLine(to: p(54, 22)); cat.closeSubpath()
            ctx.fill(cat, with: .color(theme[\.sky]))
            var tail = Path()
            let sway = t.map { 4 * sin($0 * 1.6) } ?? 0
            tail.move(to: p(33, 53)); tail.addCurve(to: p(20 + sway, 72), control1: p(20, 55), control2: p(17 + sway / 2, 63))
            ctx.stroke(tail, with: .color(theme[\.sky]), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            // A blink of ~0.15 s every 4 s.
            let eye = t.map { $0.truncatingRemainder(dividingBy: 4) < 0.15 ? 0.6 : 3.6 } ?? 3.6
            for x in [41.0, 49] { ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: 26 - eye / 2, width: 3.6, height: eye)), with: .color(theme[\.base])) }
        }
    }
}

/// The logo opens Settings: a wider target than the picture, and a soft plate under the pointer so it reads as a button.
private struct LogoButton: View {
    let logo: NSImage?
    let small: Bool
    let onLogo: () -> Void
    @State private var hover = false
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let logo { Image(nsImage: logo).resizable().scaledToFit() } else { GzymsLogo() }
        }
        .frame(width: small ? 16 : 22, height: small ? 15 : 21)
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme[\.surface].opacity(hover ? 1 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .pointerStyle(.link)
        .help("Gzyms Settings")
        .onTapGesture(perform: onLogo)
    }
}
