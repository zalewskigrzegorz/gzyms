import AppKit
import GzymsCore
import SwiftUI
import Testing
@testable import GzymsUI

let fixedNow = Date(timeIntervalSince1970: 1_793_400_000)  // 2026-10-30, a fixed clock

/// Every preview is checked against its pattern in Snapshots/ (Greg, 2026-10-31: a look test before each deploy).
/// A changed look fails the test and leaves the new picture in $TMPDIR/gzyms-snapshots. Meant it? Then
/// `GZYMS_RECORD=1 swift test` writes the new patterns. `GZYMS_PREVIEW_DIR=<dir>` also copies every PNG there.
@MainActor func preview(_ view: some View, _ name: String, width: CGFloat? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    let env = ProcessInfo.processInfo.environment
    // Nothing from this Mac: every file icon is the same drawn square.
    let v = NSHostingView(rootView: view.environment(\.fileIcon) { _ in fakeIcon }.environment(\.fixedNow, fixedNow))
    v.frame = NSRect(origin: .zero, size: width.map { NSSize(width: $0, height: 36) } ?? v.fittingSize)
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds), let png = { v.cacheDisplay(in: v.bounds, to: rep)
        return rep.representation(using: .png, properties: [:]) }() else { Issue.record("\(name): could not render", sourceLocation: sourceLocation); return }
    if let dir = env["GZYMS_PREVIEW_DIR"] { try? png.write(to: URL(filePath: dir).appending(path: "\(name).png")) }

    let pattern = snapshotDir.appending(path: "\(name).png")
    guard env["GZYMS_RECORD"] != "1", let old = NSBitmapImageRep(data: (try? Data(contentsOf: pattern)) ?? Data()) else {
        try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        try? png.write(to: pattern)
        if env["GZYMS_RECORD"] != "1" { Issue.record("\(name): no pattern yet, wrote \(pattern.path). Look at it, then run again.", sourceLocation: sourceLocation) }
        return
    }
    let changed = pixelsChanged(old, rep)
    guard changed > 0.002 else { return }  // anti-aliasing noise stays under 0.2 % of the pixels
    let out = FileManager.default.temporaryDirectory.appending(path: "gzyms-snapshots")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try? png.write(to: out.appending(path: "\(name).png"))
    Issue.record("\(name): looks different (\(String(format: "%.1f", changed * 100)) % of pixels). New picture: \(out.path)/\(name).png",
                 sourceLocation: sourceLocation)
}

/// An app or file icon that is the same on every Mac: a rounded square in two colours.
let fakeIcon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
    NSColor(deviceRed: 0.55, green: 0.3, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: r.insetBy(dx: 4, dy: 4), xRadius: 14, yRadius: 14).fill()
    NSColor(deviceRed: 0.55, green: 0.91, blue: 0.99, alpha: 1).setFill()
    NSBezierPath(ovalIn: r.insetBy(dx: 20, dy: 20)).fill()
    return true
}

private let snapshotDir = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Snapshots")

/// Share of pixels where a channel moved by more than 16 of 255; a different size counts as all of them.
func pixelsChanged(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 1 }
    let (pa, pb) = (rgba(a), rgba(b))
    if pa == pb { return 0 }
    var changed = 0
    pa.withUnsafeBufferPointer { x in
        pb.withUnsafeBufferPointer { y in
            var i = 0
            while i < x.count {
                if abs(Int(x[i]) - Int(y[i])) > 16 || abs(Int(x[i + 1]) - Int(y[i + 1])) > 16
                    || abs(Int(x[i + 2]) - Int(y[i + 2])) > 16 || abs(Int(x[i + 3]) - Int(y[i + 3])) > 16 { changed += 1 }
                i += 4
            }
        }
    }
    return Double(changed) / Double(max(1, pa.count / 4))
}

/// The picture as plain RGBA bytes, whatever layout the rep keeps them in.
private func rgba(_ rep: NSBitmapImageRep) -> [UInt8] {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { buf in
        guard let cg = rep.cgImage, let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return bytes
}

@Test func pixelsChangedSeesARealChangeOnly() throws {
    // Device RGB colours: the rep stores only what it can map straight.
    func grey(_ v: Double) -> NSColor { NSColor(deviceRed: v, green: v, blue: v, alpha: 1) }
    func rep(_ v: Double, dot: Bool = false) -> NSBitmapImageRep {
        let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<10 { for y in 0..<10 { r.setColor(grey(v), atX: x, y: y) } }
        if dot { r.setColor(grey(1), atX: 3, y: 3) }
        return r
    }
    #expect(pixelsChanged(rep(0), rep(0)) == 0)
    #expect(pixelsChanged(rep(0), rep(0, dot: true)) == 0.01)
    #expect(pixelsChanged(rep(0), rep(0.03)) == 0)  // under the noise floor
}

@MainActor @Test func redrawComparesOnlyItsKey() {
    let a = Redraw(1, "x") { Text("a") }, b = Redraw(1, "x") { Text("other content, same key") }
    #expect(a == b)  // the content (and its closures) never decides
    #expect(Redraw(1, "x") { EmptyView() } != Redraw(2, "x") { EmptyView() })
}

@MainActor @Test func previews() {
    let ws = [BarWorkspace(number: 1, color: "green", isActive: true, appBundleIDs: []),
              BarWorkspace(number: 2, color: "peach", isActive: false, appBundleIDs: [])]
    let series = (0..<30).map { Double($0 * 3 % 70) + 5 }
    let mem = MemorySample(used: 31 << 30, total: 36 << 30, swap: 1_288_490_189)
    // The two own themes and four terminal palettes, dark and light: enough to see the mapping hold.
    for theme in Theme.builtIn + ["dracula", "nord", "catppuccin_latte", "gruvbox_light"].compactMap(Theme.named) {
        preview(BarView(workspaces: ws, small: false, notch: nil, stale: false, now: fixedNow, cpu: 12, cpuSeries: series,
                        memory: mem, icon: { _ in nil }).environment(\.theme, theme), "bar-\(theme.name)", width: 900)
    }
    // A laptop-like notch with a long track: the title gives way, nothing slides under the notch.
    let song = NowPlaying(title: "Pray for Silence (Extended Version)", artist: "Some Band", playing: true, at: fixedNow.timeIntervalSince1970)
    preview(BarView(workspaces: ws, small: false, notch: NotchGap(minX: 660, maxX: 852), stale: false, now: fixedNow, cpu: 12,
                    cpuSeries: series, memory: mem, icon: { _ in nil }, media: mediaItems(song, tabs: [], now: fixedNow.timeIntervalSince1970)),
            "bar-notch-music", width: 1512)
    preview(TopProcessesView(top: [ProcessCPU(pid: 1, name: "Vimma", percent: 14.2)]), "cpu-popup")
    preview(MemoryDetailsView(memory: mem), "memory-popup")
    let net = NetSample(down: 1_234_000, up: 30_400, kind: .wifi, ip: "192.168.1.23", tailscale: "100.90.5.9", proxy: "127.0.0.1:9090")
    let down = (0..<60).map { $0 % 9 == 0 ? 3e6 : 2e5 }, up = (0..<60).map { $0 % 7 == 0 ? 6e5 : 3e4 }
    preview(NetworkView(net: net, small: false), "net-pill-proxy")
    preview(NetworkDetailsView(net: net, down: down, up: up), "net-popup")
    let weak = BatterySample(percent: 78, plugged: true, charging: false, adapterW: 30, systemW: 44, batteryW: -14)
    preview(BatteryView(battery: weak, warning: .chargerTooWeak, small: false), "battery-pill-weak")
    preview(BatteryDetailsView(battery: weak), "battery-popup")
    func banner(_ level: NotifyLevel, body: String?, reminder: Bool = false) -> GzymsNotification {
        GzymsNotification(id: "p", app: nil, level: level, title: "Build finished", subtitle: "gzyms · main", body: body,
                          link: nil, altLink: nil, sound: nil, at: fixedNow, reminder: reminder)
    }
    preview(BannerView(n: banner(.info, body: "All 112 tests green."), icon: nil, remaining: 4, total: 6, topInset: 30), "banner-info")
    let long = "The release build failed on GzymsUI because a view picked a colour of its own instead of a theme token, "
        + "and the check script stops at the first red test so nothing after it ran."
    preview(BannerView(n: banner(.error, body: long), icon: nil, remaining: 3, total: 12, topInset: 32), "banner-error-long-body")
    preview(BannerView(n: banner(.critical, body: "Disk almost full."), icon: nil, remaining: nil, total: nil), "banner-critical")
    preview(BannerView(n: banner(.info, body: "Standup in 3 min.", reminder: true), icon: nil, remaining: nil, total: nil),
            "banner-reminder")
    preview(BannerView(n: banner(.info, body: "All 112 tests green."), icon: nil, remaining: 4, total: 6, hints: ChordHints(snoozeMinutes: nil)),
            "banner-hints")
    preview(BannerView(n: banner(.info, body: "All 112 tests green."), icon: nil, remaining: 4, total: 6, hints: ChordHints(snoozeMinutes: 10)),
            "banner-hints-snooze")
    var named = banner(.info, body: "Agent 3 waits for you.")
    named.altLink = "https://example.com"
    named.altLabel = "Open in agent"
    preview(BannerView(n: named, icon: nil, remaining: 4, total: 6, hints: ChordHints(snoozeMinutes: nil, hold: "⌃")), "banner-hints-named-alt")
    preview(BannerView(n: banner(.warning, body: "Three more wait under it."), icon: nil, remaining: 4, total: 8,
                       hints: ChordHints(snoozeMinutes: nil), topInset: 30, queue: [banner(.error, body: nil), banner(.info, body: nil), banner(.info, body: nil, reminder: true)]), "banner-stack")
    var reminder = banner(.info, body: "Standup in 3 min.", reminder: true)
    reminder.id = "r"
    reminder.at = fixedNow.addingTimeInterval(-120)
    let older = GzymsNotification(id: "o", app: nil, level: .info, title: "Deploy done", subtitle: nil, body: nil, link: nil, altLink: nil,
                                  sound: nil, at: fixedNow.addingTimeInterval(-3600))
    preview(BannerView(n: .pending(app: "com.app", at: fixedNow), icon: nil, remaining: nil, total: nil), "banner-pending")
    preview(InboxList(notes: [reminder, older]), "inbox-list")
    preview(BellView(notes: [older], small: false), "bell")
    var np = NowPlaying(title: "Midnight City", artist: "M83", app: "com.spotify.client", appName: "Spotify", playing: true,
                        elapsed: 75, duration: 243, at: Date().timeIntervalSince1970)
    let music = mediaItems(np, tabs: [], now: np.at)
    let icon: (String) -> NSImage? = { _ in fakeIcon }
    preview(MusicView(items: music, small: false, icon: icon) { _ in }, "music-pill")
    preview(MusicView(items: music, small: false, icon: icon) { _ in }.frame(width: 120), "music-pill-short")
    preview(MusicView(items: music, small: false, icon: icon) { _ in }.frame(width: 60), "music-pill-icon")
    // Music, a film in a tab and an app that can only be gone to: the tail icons, then the icons alone.
    np.others = [MediaSource(app: "com.apple.podcasts", appName: "Podcasts", title: "A talk", playing: false)]
    let film = BrowserTab(id: "t", url: "https://www.youtube.com/watch?v=1", media: [.init(i: 0, title: "Art being a rizz master", playing: true)])
    let many = mediaItems(np, tabs: [film], now: np.at)
    preview(MusicView(items: many, small: false, icon: icon) { _ in }, "music-pill-sources")
    preview(MusicView(items: many, small: false, icon: icon) { _ in }.frame(width: 70), "music-pill-sources-icons")
    preview(MusicDetailsView(items: many, icon: icon) { _ in }, "music-popup")
    let awake = CaffeineState(until: fixedNow.addingTimeInterval(105 * 60))
    preview(HStack { CaffeineView(state: nil, now: fixedNow, small: false) { _ in }; CaffeineView(state: awake, now: fixedNow, small: false) { _ in } },
            "caffeine-pills")
    preview(CaffeinePopup(state: awake, now: fixedNow) { _ in }, "caffeine-popup")
    let quiet = fixedNow.addingTimeInterval(45 * 60)
    preview(HStack { DNDView(until: nil, now: fixedNow, small: false) { _ in }; DNDView(until: quiet, now: fixedNow, small: false) { _ in } },
            "dnd-pills")
    preview(DNDPopup(until: quiet, now: fixedNow) { _ in }, "dnd-popup")
    let load: [Double] = [5, 10, 20, 40, 95, 60, 30, 15, 8, 12, 85, 20]
    preview(HStack { CPUView(percent: 20, series: load, chart: .line, small: false); CPUView(percent: 20, series: load, chart: .bars, small: false) },
            "cpu-charts")
    preview(BarChart(values: load, threshold: 50, floor: 10, unit: "%").frame(width: 360).padding(8), "hud-chart")
    let parked = ["/fake/Report.pdf", "/fake/screenshot with a long name.png", "/fake/notes.md"].map { URL(fileURLWithPath: $0) }
    preview(HStack { ShelfView(files: [], small: false, dropping: true) { _ in }; ShelfView(files: parked, small: false, dropping: false) { _ in } },
            "shelf-pills")
    preview(ShelfPopup(files: parked) { _ in }, "shelf-popup")
    preview(HStack { ShelfDropZoneView(topInset: 32) { _ in }.frame(width: 340, height: 128)
        ShelfDropZoneView(topInset: 0, over: true) { _ in }.frame(width: 340, height: 96) }, "shelf-drop-zone")
    preview(PluginMenuView(rows: [
        PluginRow(id: "ev:1", text: "#1204  CI failed: e2e  fix(cart): keep the coupon when the basket is split in two", tag: "✗ CI", color: "red", detail: "19:02"),
        PluginRow(separator: true),
        PluginRow(id: "pr:1", text: "#1187  fix(login): show a clear error when the sign-in service is down", tag: "resolve", color: "sky", detail: "💬 1"),
        PluginRow(id: "pr:2", text: "dotfiles#42  Move the shell prompt to a theme of its own", tag: "blocked", color: "lavender"),
    ]) { _, _ in }, "plugin-menu")
}

@MainActor @Test func bellWidthIsFixedForOneAndNineteen() {
    func width(_ n: Int) -> CGFloat {
        let notes = (0..<n).map { GzymsNotification(id: "\($0)", app: nil, level: .info, title: "t", subtitle: nil, body: nil,
                                                    link: nil, altLink: nil, sound: nil, at: fixedNow) }
        return NSHostingView(rootView: BellView(notes: notes, small: false)).fittingSize.width
    }
    #expect(width(1) == width(19))
}

/// 35 notifications ran off the screen and took Clear all with them (Greg, 2026-11-02): a popup stops at its cap and scrolls.
@MainActor @Test func popupStopsAtItsMaxHeight() {
    func size(_ n: Int) -> NSSize {
        let notes = (0..<n).map { GzymsNotification(id: "\($0)", app: nil, level: .info, title: "t", subtitle: nil, body: nil,
                                                    link: nil, altLink: nil, sound: nil, at: fixedNow) }
        return NSHostingView(rootView: InboxList(notes: notes).environment(\.popupMaxHeight, 300)).fittingSize
    }
    #expect(size(50).height > 300 && size(50).height <= 300 + 60)  // the list's cap plus the header and padding
    #expect(size(50).width == 320)
    #expect(size(2).height < size(3).height)  // a short list keeps its own height
    #expect(size(3).height < 300)
}

@MainActor @Test func batteryWidthIsFixedWithoutWarning() {
    let a = BatterySample(percent: 5, plugged: false, charging: false, adapterW: nil, systemW: nil, batteryW: -5)
    let b = BatterySample(percent: 100, plugged: true, charging: true, adapterW: 96, systemW: 20, batteryW: 30)
    #expect(width(BatteryView(battery: a, warning: nil, small: false)) == width(BatteryView(battery: b, warning: nil, small: false)))
}

@MainActor @Test func networkWidthIsFixed() {
    let quiet = NetSample(down: 0, up: 0, kind: .wifi, ip: nil, tailscale: nil, proxy: nil)
    let busy = NetSample(down: 98_700_000, up: 1_234_000, kind: .ethernet, ip: nil, tailscale: nil, proxy: "127.0.0.1:9090")
    for small in [false, true] {
        #expect(width(NetworkView(net: quiet, small: small)) == width(NetworkView(net: busy, small: small)))
        #expect(width(NetworkView(net: quiet, small: small)) == width(NetworkView(net: nil, small: small)))
    }
}

@Test func viewsHaveNoColourOfTheirOwn() throws {
    // Colours live in Theme (GzymsCore), so a new theme recolours everything.
    let ui = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/GzymsUI").standardized
    for file in try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil) {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.firstMatch(of: /"#[0-9A-Fa-f]{6}"|Color\.(gray|red|green|blue|white|black)\b|NSColor\./) == nil, "\(file.lastPathComponent)")
    }
}

@MainActor func width(_ view: some View) -> NSSize { NSHostingView(rootView: view).fittingSize }

@MainActor @Test func cpuWidthIsFixed() {
    #expect(width(CPUView(percent: 3, series: [], small: false)) == width(CPUView(percent: 100, series: [], small: false)))
    #expect(width(CPUView(percent: 3, series: [], small: false)) == width(CPUView(percent: nil, series: [], small: false)))
    #expect(width(CPUView(percent: 3, series: [], small: true)) == width(CPUView(percent: 100, series: [], small: true)))
}

@MainActor @Test func memoryWidthIsFixed() {
    let low = MemorySample(used: 1 << 30, total: 36 << 30, swap: 0), full = MemorySample(used: 36 << 30, total: 36 << 30, swap: 0)
    for small in [false, true] {
        #expect(width(MemoryView(memory: low, small: small)) == width(MemoryView(memory: full, small: small)))
        #expect(width(MemoryView(memory: low, small: small)) == width(MemoryView(memory: nil, small: small)))
    }
}

@MainActor @Test func clockWidthIsFixed() {
    let cal = Calendar.current
    let morning = cal.date(bySettingHour: 9, minute: 5, second: 0, of: fixedNow)!
    let night = cal.date(bySettingHour: 23, minute: 59, second: 0, of: fixedNow)!
    #expect(width(ClockView(now: morning, small: false)) == width(ClockView(now: night, small: false)))
}

@MainActor @Test func contentStaysOutOfTheNotch() {
    // The left stack starts after the bar's horizontal padding, so its width must leave that out too.
    #expect(BarLayout.leftWidth(total: 900, notch: NotchGap(minX: 330, maxX: 570)) == 330 - BarLayout.notchMargin - BarLayout.horizontalPadding)
    #expect(BarLayout.leftWidth(total: 900, notch: nil) == nil)
    #expect(BarLayout.rightWidth(total: 900, notch: NotchGap(minX: 330, maxX: 570)) == 330 - BarLayout.notchMargin - BarLayout.horizontalPadding)
    #expect(BarLayout.rightWidth(total: 900, notch: nil) == nil)
}

@MainActor @Test func notchGapFromAuxiliaryAreaWidths() {
    // Widths only, so it holds wherever the screen sits in global coordinates.
    #expect(NotchGap(screenWidth: 1512, leftAreaWidth: 650, rightAreaWidth: 650) == NotchGap(minX: 650, maxX: 862))
}

@MainActor @Test func settingsPreviews() {
    var config = GzymsConfig.defaults
    config.appRules["com.tinyspeck.slackmacgap"] = AppRule(sound: false, level: .critical)
    let apps = [SeenApp(id: "com.tinyspeck.slackmacgap", name: "Slack", icon: nil, mac: NCAppSettings(center: false, sound: true)),
                SeenApp(id: "com.readdle.SparkDesktop", name: "Spark", icon: nil),
                SeenApp(id: "com.apple.MobileSMS", name: "Messages", icon: nil, mac: NCAppSettings())]
    let actions = SettingsActions { _, _, _ in }
    for tab in SettingsTab.allCases {
        preview(SettingsView(tab: .constant(tab), config: config, problems: [], broken: false, apps: apps,
                             devices: ["MacBook Pro Speakers", "Shure MV7"], workspaceNames: [1: "chat", 2: "term"], actions: actions).frame(width: 1000, height: 900),
                "settings-\(tab.rawValue)")
    }
    var updating = actions
    updating.canCheckForUpdates = true
    preview(SettingsView(tab: .constant(.about), config: config, problems: [], broken: false, apps: apps,
                         devices: [], live: false, actions: updating).frame(width: 1000, height: 900), "settings-about-updates")
    preview(SettingsView(tab: .constant(.notifications), config: config, problems: [], broken: false, apps: apps,
                         devices: [], actions: actions).frame(width: 1800, height: 700), "settings-notifications-wide")
    preview(SettingsView(tab: .constant(.apps), config: config, problems: [], broken: false, apps: apps,
                         devices: [], actions: actions).frame(width: 1800, height: 700), "settings-apps-wide")
    // The app open on the side: preset, More folded, its macOS page with what to change ringed.
    preview(SettingsView(tab: .constant(.apps), config: config, problems: [], broken: false, apps: apps, devices: [], live: false,
                         openApp: "com.tinyspeck.slackmacgap", actions: actions).frame(width: 1200, height: 900), "settings-apps-drawer")
    preview(SettingsView(tab: .constant(.general), config: config, problems: ["config.toml could not be read: line 3"], broken: true,
                         apps: [], devices: [], actions: actions).frame(width: 1000, height: 400), "settings-broken")
    let pr = PluginStatus(folder: "pr-watch", name: "PR watch", description: "Your PRs on the bar", enabled: true, running: true, options: [
        PluginOption(key: "repos", title: "Repos", kind: .list, defaultValue: .strings(["acme/web"])),
        PluginOption(key: "sound", title: "Sound on events", kind: .toggle, defaultValue: .bool(true)),
        PluginOption(key: "who", title: "Whose PRs", kind: .choice, defaultValue: .string("mine"), choices: ["mine", "team"]),
    ])
    preview(SettingsView(tab: .constant(.plugins), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: [pr], actions: actions).frame(width: 1400, height: 900), "settings-plugin-options")
    preview(SettingsView(tab: .constant(.modules), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: [pr], actions: actions).frame(width: 1400, height: 900), "settings-built-in")
    let ag = PluginStatus(folder: "agents", name: "Agents", description: "The coding agents tuios sees", enabled: true, running: true, options: [
        PluginOption(key: "done_after", title: "Done after (min)", kind: .number, defaultValue: .int(3)),
        PluginOption(key: "terminal", title: "Terminal", kind: .text, defaultValue: .string("Ghostty")),
    ])
    preview(SettingsView(tab: .constant(.agents), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: [ag], actions: actions).frame(width: 1400, height: 500), "settings-agents-on")
}

@Test func everyDeviceKindHasASymbol() {
    for kind in AudioDevice.Kind.allCases {
        for input in [true, false] {
            for muted in [true, false] {
                let name = deviceSymbol(kind, input: input, muted: muted)
                #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(kind) \(name)")
            }
        }
    }
}

@MainActor @Test func permissionsPreviews() {
    let states = [GrantState(grant: .accessibility, granted: true), GrantState(grant: .fullDiskAccess, granted: false)]
    preview(PermissionsWizardView(states: states, open: { _ in }, later: {}), "wizard-missing-fda")
    preview(AppSetupView(app: SeenApp(id: "com.x", name: "Messages", icon: nil, mac: NCAppSettings(desktop: false, sound: true)),
                         step: 2, total: 4, skip: {}, stop: {}), "app-setup")
    preview(BarView(workspaces: [], small: false, notch: nil, stale: false, now: fixedNow, icon: { _ in nil }, grantWarning: true),
            "bar-grant-revoked", width: 900)
}

@MainActor @Test func armageddonFlashesTwiceASecondOrPulsesCalm() {
    // On and off every 0.25 s: two flashes a second, under the three a second photosensitivity limit.
    #expect([0.0, 0.25, 0.5, 0.75, 1.0].map { ArmageddonView.red(at: $0, calm: false) } == [1, 0, 1, 0, 1])
    #expect((0...20).map { ArmageddonView.red(at: Double($0) / 10, calm: true) }.allSatisfy { (0.5...1).contains($0) })
    let n = GzymsNotification(id: "a", app: nil, level: .armageddon, title: "Prod is down", subtitle: "api-eu: 502 for 3 min",
                              body: "error rate 64%", link: nil, altLink: nil, sound: nil, at: fixedNow)
    preview(ArmageddonView(n: n, icon: nil, calm: false, at: Date(timeIntervalSinceReferenceDate: 0)).frame(width: 1200, height: 760)
        .environment(\.theme, Theme.all[0]), "armageddon")
}

@MainActor @Test func gzymsMessageLooksLikeTheTheme() {
    preview(GzymsMessageView(title: "Gzyms was not tested on macOS 28", lines: ["Some parts may not work right.", "If something breaks, a report helps fix it."],
                             actions: [.init("Turn on debug mode") {}, .init("Report a problem") {}], close: {})
        .themed(.mochaNeon), "gzyms-message")
    // Lines are inline markdown: code in backticks and a link.
    preview(GzymsMessageView(title: "What's new in Gzyms 0.0.2", lines: ["`gzyms skill` teaches coding agents.", "Learn the keys at [gzyms.dev/try](https://gzyms.dev/try/)."],
                             actions: [.init("Learn the keys") {}], close: {})
        .themed(.mochaNeon), "gzyms-whats-new")
}

@Test func hintRowsCarryTheirActions() {
    let rows = ChordHints(snoozeMinutes: nil, hold: "⌃").rows(alt: "Open in agent", waiting: 2)
    #expect(rows.map { $0.map(\.text) } == [["⌃O open", "⌃X dismiss", "⌃Z snooze"], ["⌃A Open in agent"], ["⌃N next", "⌃P prev", "2 more"]])
    #expect(rows.flatMap { $0.map(\.action) } == [.open, .dismiss, .snooze(minutes: 3), .alt, .next, .previous, nil])
    #expect(ChordHints(snoozeMinutes: nil).rows(alt: nil).count == 1)  // no second action: no alt line
    #expect(ChordHints(snoozeMinutes: nil, note: "No second action").rows(alt: "x") == [[HintItem("No second action")]])
}
