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
    // Whose count: the app's own Dock badge, Gzyms's list, both.
    for theme in Theme.builtIn + ["catppuccin_latte"].compactMap(Theme.named) {
        let apps = BarWorkspace(number: 1, color: "green", isActive: true, appBundleIDs: ["app", "gzyms", "both", "many"])
        preview(WorkspaceItem(ws: apps, small: false, icon: { _ in fakeIcon }, inboxes: ["gzyms": [older, reminder], "both": [older], "many": [older, reminder]])
            .padding(10).background(theme[\.base]).environment(\.theme, theme)
            .environment(\.dockBadges, ["app": "3", "both": "12", "many": "998"]),
        "app-counts-\(theme.name)")
    }
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
        PluginRow(id: "ev:1", text: "#1204  CI failed: e2e  fix(cart): keep the coupon when the basket is split in two", tag: ":xmark.circle: CI", color: "red", detail: "19:02"),
        PluginRow(separator: true),
        PluginRow(id: "pr:1", text: "#1187  fix(login): show a clear error when the sign-in service is down", tag: "resolve", color: "sky", detail: ":bubble.left: comments"),
        PluginRow(id: "pr:2", text: "dotfiles#42  Move the shell prompt to a theme of its own", tag: "blocked", color: "lavender"),
    ]) { _, _ in }, "plugin-menu")
    // The GitHub pills as the plugins print them: one glyph per state with the number of PRs (runs) in it, the same glyph and word in the list.
    func pill(_ plugin: String, _ text: String, _ icon: String, _ color: String) -> some View {
        let item = PluginItem(id: plugin, text: text, icon: icon, color: color)
        return VStack(alignment: .leading, spacing: 8) {
            PluginPillView(pill: PluginPill(plugin: plugin, item: item), small: true) { _, _ in }
            PluginPillView(pill: PluginPill(plugin: plugin, item: item), small: false) { _, _ in }
        }.padding(8)
    }
    preview(pill("gh-prs", ":xmark.circle@red: 2 :checkmark.circle@green: 1 :bubble.left@sky: 3 :square.and.pencil@mauve: 1", "arrow.triangle.branch", "red"), "gh-prs-pill")
    // Every row says its state and what its CI did, a draft too. Green passed, red failed, gold waiting.
    preview(PluginMenuView(rows: [
        PluginRow(id: "pr:o/r#31", text: "r#31  fix(cart): keep the coupon when the basket is split", tag: ":xmark.circle: fix", color: "red",
                  detail: ":xmark.circle@red: failed  :bubble.left@sky: comments"),
        PluginRow(id: "pr:o/r#30", text: "r#30  fix(login): show a clear error when sign-in is down", tag: ":xmark.circle: fix", color: "red",
                  detail: ":checkmark.circle@green: passed  :exclamationmark.triangle@red: conflict"),
        PluginRow(id: "pr:o/r#29", text: "r#29  feat(api): paginate the list", tag: ":xmark.circle: fix", color: "red",
                  detail: ":arrow.triangle.2.circlepath@gold: running  :exclamationmark.circle@peach: changes requested"),
        PluginRow(id: "pr:o/r#28", text: "r#28  chore(deps): bump the router", tag: ":checkmark.circle: merge", color: "green", detail: ":checkmark.circle@green: passed"),
        PluginRow(id: "pr:o/r#27", text: "r#27  feat(search): rank by recency", tag: ":hourglass: review?", color: "gold", detail: ":checkmark.circle@green: passed"),
        PluginRow(id: "pr:o/r#26", text: "r#26  perf(db): add an index", tag: ":arrow.triangle.2.circlepath: CI runs", color: "gold", detail: ":arrow.triangle.2.circlepath@gold: running"),
        PluginRow(id: "pr:o/r#24", text: "r#24  fix(auth): refresh the token", tag: ":checkmark.bubble: resolve", color: "peach", detail: ":checkmark.circle@green: passed"),
        PluginRow(id: "pr:o/r#23", text: "r#23  docs: the new setup", tag: ":lock.circle: blocked", color: "peach", detail: ":circle.dashed: no CI"),
        PluginRow(id: "pr:o/r#25", text: "r#25  wip: move the prompt to a theme", tag: ":square.and.pencil: draft", color: "mauve",
                  detail: ":checkmark.circle@green: passed  :bubble.left@sky: comments"),
    ]) { _, _ in }, "gh-prs-popup")
    preview(pill("gh-builds", ":xmark.circle@red: 1 :arrow.triangle.2.circlepath@gold: 2 :checkmark.circle@green: 5", "hammer", "red"), "gh-builds-pill")
    preview(PluginMenuView(rows: [
        PluginRow(id: "t:o/r#31", text: "r#31  fix(cart): keep the coupon when the basket is split", tag: ":xmark.circle: failed", color: "red", detail: "unit, lint"),
        PluginRow(id: "t:o/r#28", text: "r#28  chore(deps): bump the router", tag: ":arrow.triangle.2.circlepath: running", color: "gold"),
        PluginRow(id: "t:o/r@main", text: "r@main", tag: ":arrow.triangle.2.circlepath: running", color: "gold"),
        PluginRow(id: "t:o/r#27", text: "r#27  feat(search): rank by recency", tag: ":checkmark.circle: passed", color: "green"),
        PluginRow(id: "t:o/r#22", text: "r#22  ci: a check waits for an action", tag: ":minus.circle: done", color: "overlay"),
        PluginRow(id: "t:o/r#21", text: "r#21  docs: the new setup", tag: ":circle.dashed: no CI", color: "overlay"),
    ]) { _, _ in }, "gh-builds-popup")
    // A pill that cannot get its data greys out with a small warning. Its popup says what broke and since when, the old rows sit under it dimmed (#62).
    let utc = TimeZone(identifier: "UTC")!
    let broke = PluginFailure(message: "gh is logged out. Run gh auth login in a terminal. This pill updates by itself after that.", since: fixedNow.addingTimeInterval(-1800))
    let oldPill = PluginItem(id: "prs", text: ":xmark.circle@red: 2 :checkmark.circle@green: 1", icon: "arrow.triangle.branch", color: "red")
    preview(VStack(alignment: .leading, spacing: 8) {
        PluginPillView(pill: PluginPill(plugin: "gh-prs", item: oldPill), small: false) { _, _ in }
        PluginPillView(pill: PluginPill(plugin: "gh-prs", item: oldPill, failure: broke), small: true) { _, _ in }
        PluginPillView(pill: PluginPill(plugin: "gh-prs", item: oldPill, failure: broke), small: false) { _, _ in }
    }.padding(8).environment(\.timeZone, utc), "plugin-pill-failed")
    preview(PluginMenuView(rows: [
        PluginRow(id: "pr:o/r#31", text: "r#31  fix(cart): keep the coupon when the basket is split", tag: ":xmark.circle: fix", color: "red", detail: ":xmark.circle@red: failed"),
        PluginRow(id: "pr:o/r#28", text: "r#28  chore(deps): bump the router", tag: ":checkmark.circle: merge", color: "green", detail: ":checkmark.circle@green: passed"),
    ], failure: broke) { _, _ in }.environment(\.timeZone, utc), "plugin-popup-failed")
    preview(PluginMenuView(rows: [], failure: PluginFailure(message: "The plugin stopped (exit 1). Starting it again in 4 s.", since: fixedNow.addingTimeInterval(-90))) { _, _ in }
        .environment(\.timeZone, utc), "plugin-popup-failed-alone")
    // The star watcher: a gold star with the total, a row per repo.
    preview(pill("star-watcher", "15", "star.fill", "gold"), "star-watcher-pill")
    preview(PluginMenuView(rows: [
        PluginRow(id: "zalewskigrzegorz/gzyms", text: "zalewskigrzegorz/gzyms", detail: ":star.fill@gold: 12"),
        PluginRow(id: "zalewskigrzegorz/tuios", text: "zalewskigrzegorz/tuios", detail: ":star.fill@gold: 3"),
        PluginRow(text: "Not found: zalewskigrzegorz/gone"),
    ]) { _, _ in }, "star-watcher-popup")
    // An agent's notification sits on the agents pill and tops its list, not in the bell (#50).
    var waits = older
    waits.id = "plugin:agents:agent-1"
    waits.title = "Orchestrator waits for you"
    waits.body = "approve AskUserQuestion"
    let agents = PluginPill(plugin: "agents", item: PluginItem(id: "agents", text: "1", icon: "sparkles", color: "peach"))
    preview(PluginPillView(pill: agents, small: false, notes: [waits]) { _, _ in }.padding(6), "plugin-pill-count")
    preview(PluginMenuView(rows: [PluginRow(id: "w1", text: "Orchestrator", tag: "waits", color: "peach", detail: "gzyms")],
                           notes: [waits]) { _, _ in }, "plugin-menu-notes")
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
    let apps = [SeenApp(id: "com.tinyspeck.slackmacgap", name: "Slack", icon: nil, mac: NCAppSettings(center: false, sound: true, shortcutOff: true)),
                SeenApp(id: "com.readdle.SparkDesktop", name: "Spark", icon: nil),
                SeenApp(id: "com.apple.MobileSMS", name: "Messages", icon: nil, mac: NCAppSettings())]
    let actions = SettingsActions { _, _, _ in }
    for tab in SettingsTab.allCases {
        preview(SettingsView(tab: .constant(tab), config: config, problems: [], broken: false, apps: apps,
                             devices: ["MacBook Pro Speakers", "Shure MV7"], workspaceNames: [1: "chat", 2: "term"], workspacesFound: true, actions: actions).frame(width: 1000, height: 900),
                "settings-\(tab.rawValue)")
    }
    var dupes = actions
    dupes.duplicates = {
        DuplicatesState(groups: [DuplicateGroup(apps: ["com.apple.iCal", "com.readdle.SparkDesktop"], count: 7, last: fixedNow - 300),
                                 DuplicateGroup(apps: ["com.apple.MobileSMS", "com.readdle.SparkDesktop", "com.tinyspeck.slackmacgap"], count: 1, last: fixedNow - 86_400)])
    }
    preview(SettingsView(tab: .constant(.debug), config: config, problems: [], broken: false, apps: apps, devices: [],
                         actions: dupes).frame(width: 1000, height: 900), "settings-debug-duplicates")
    var dev = actions
    dev.loginItem = { nil }
    preview(SettingsView(tab: .constant(.general), config: config, problems: [], broken: false, apps: [], devices: [],
                         actions: dev).frame(width: 1000, height: 300), "settings-general-dev")
    var denied = actions
    denied.loginItem = { .requiresApproval }
    preview(SettingsView(tab: .constant(.general), config: config, problems: [], broken: false, apps: [], devices: [],
                         actions: denied).frame(width: 1000, height: 300), "settings-general-denied")
    var updating = actions
    updating.canCheckForUpdates = true
    preview(SettingsView(tab: .constant(.about), config: config, problems: [], broken: false, apps: apps,
                         devices: [], live: false, actions: updating).frame(width: 1000, height: 900), "settings-about-updates")
    // Homebrew: Sparkle off with the note, then turned on by the user with the warning.
    updating.homebrew = true
    preview(SettingsView(tab: .constant(.about), config: config, problems: [], broken: false, apps: apps,
                         devices: [], live: false, actions: updating).frame(width: 1000, height: 900), "settings-about-homebrew")
    var chosen = config
    chosen.updatesAutomatic = true
    preview(SettingsView(tab: .constant(.about), config: chosen, problems: [], broken: false, apps: apps,
                         devices: [], live: false, actions: updating).frame(width: 1000, height: 900), "settings-about-homebrew-on")
    // Homebrew found a newer version: how to get it, with Copy and the release.
    updating.newVersion = { "0.0.3" }
    preview(SettingsView(tab: .constant(.about), config: config, problems: [], broken: false, apps: apps,
                         devices: [], live: false, actions: updating).frame(width: 1000, height: 900), "settings-about-new-version")
    preview(SettingsView(tab: .constant(.notifications), config: config, problems: [], broken: false, apps: apps,
                         devices: [], actions: actions).frame(width: 1800, height: 700), "settings-notifications-wide")
    // Pushover with one key in the Keychain: its state and Change, Remove, never the value.
    var pushover = config
    pushover.phone.format = .pushover
    pushover.phone.pushoverUser = "u-secret"
    pushover.phone.saved = [.pushover_user]
    preview(SettingsView(tab: .constant(.notifications), config: pushover, problems: [], broken: false, apps: apps,
                         devices: [], actions: actions).frame(width: 1000, height: 900), "settings-notifications-pushover")
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
    // The Plugins list: a running one, an edited catalog one, one that fails, one off. Nothing else on it.
    let changed = PluginStatus(folder: "gh-prs", name: "GitHub PRs", description: "Your pull requests through the gh CLI. One glyph per state with the number of PRs in it.",
                               enabled: true, running: true, options: [PluginOption(key: "repos", title: "Repos", kind: .list)], catalogNewer: true, icon: "arrow.triangle.branch")
    let broken = PluginStatus(folder: "log-watcher", name: "Log watcher", description: "Watches log files. A line that matches a rule becomes a notification.",
                              enabled: true, running: false, problem: "plugin.sh keeps exiting: gh: command not found", icon: "doc.text.magnifyingglass")
    let off = PluginStatus(folder: "agents", name: "Agents", description: "The coding agents tuios sees.", enabled: false, running: false)
    let all = [off, changed, broken, pr]
    preview(SettingsView(tab: .constant(.plugins), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: all, actions: actions).frame(width: 1400, height: 500), "settings-plugins-list")
    preview(SettingsView(tab: .constant(.plugins), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: all, openPlugin: "pr-watch", actions: actions).frame(width: 1400, height: 500), "settings-plugin-options")
    preview(SettingsView(tab: .constant(.plugins), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: all, openPlugin: "log-watcher", actions: actions).frame(width: 1400, height: 500), "settings-plugins-error")
    preview(SettingsView(tab: .constant(.plugins), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: all, openPlugin: "gh-prs", actions: actions).frame(width: 1400, height: 500), "settings-plugins-changed")
    preview(SettingsView(tab: .constant(.modules), config: config, problems: [], broken: false, apps: [], devices: [],
                         plugins: [pr], actions: actions).frame(width: 1400, height: 900), "settings-built-in")
    // Agents: one row per source with its live state, the open one's options on the side.
    let featuresOff = "Agent features are off. Set agents.enabled = true in the config to use this command."
    let fine: [AgentSource: AgentSourceStatus] = [.tuios: AgentSourceStatus(line: "3 agents"),
                                                  .claude: AgentSourceStatus(line: "Not installed", notInstalled: true, plugin: ClaudePluginLook(state: .missing))]
    preview(SettingsView(tab: .constant(.agents), config: config, problems: [], broken: false, apps: [], devices: [],
                         agents: fine, openPlugin: "tuios", actions: actions).frame(width: 1400, height: 400), "settings-agents-on")
    preview(SettingsView(tab: .constant(.agents), config: config, problems: [], broken: false, apps: [], devices: [],
                         agents: fine, openPlugin: "claude", actions: actions).frame(width: 1400, height: 400), "settings-agents-claude")
    // The plugin just installed: Remove, and what open sessions need. Then an install that failed, in Claude's words.
    let installed = ClaudePluginLook(state: .installed("0.1.1"), note: claudePluginReloadNote)
    preview(SettingsView(tab: .constant(.agents), config: config, problems: [], broken: false, apps: [], devices: [],
                         agents: [.tuios: AgentSourceStatus(line: "3 agents"), .claude: AgentSourceStatus(line: "1 agent", plugin: installed)],
                         openPlugin: "claude", actions: actions).frame(width: 1400, height: 400), "settings-agents-claude-installed")
    let failedRun = ClaudePluginLook(state: .missing, problem: "✘ Failed to add marketplace: git clone failed")
    preview(SettingsView(tab: .constant(.agents), config: config, problems: [], broken: false, apps: [], devices: [],
                         agents: [.tuios: AgentSourceStatus(line: "3 agents"),
                                  .claude: AgentSourceStatus(line: "Not installed", notInstalled: true, plugin: failedRun)],
                         openPlugin: "claude", actions: actions).frame(width: 1400, height: 400), "settings-agents-claude-failed")
    preview(SettingsView(tab: .constant(.agents), config: config, problems: [], broken: false, apps: [], devices: [],
                         agents: [.tuios: AgentSourceStatus(line: "Agent features are off", problem: featuresOff), .claude: AgentSourceStatus(line: "1 agent")],
                         openPlugin: "tuios", actions: actions).frame(width: 1400, height: 400), "settings-agents-error")
    var allOff = config
    allOff.agentsTuios = false
    allOff.agentsClaude = false
    preview(SettingsView(tab: .constant(.agents), config: allOff, problems: [], broken: false, apps: [], devices: [],
                         agents: [.tuios: AgentSourceStatus(line: "Off"), .claude: AgentSourceStatus(line: "Off")], actions: actions)
        .frame(width: 1400, height: 300), "settings-agents-off")
}

/// The agents popup: what waits on top with its question, idle dimmed, a failing source's rows under its message.
@MainActor @Test func agentsPopupPreview() {
    func a(_ s: AgentSource, _ name: String, _ state: AgentState, _ place: String, _ message: String = "") -> Agent {
        Agent(source: s, id: name, name: name, place: place, state: state, message: message)
    }
    let item = agentsItem([
        .claude: AgentSourceLook(agents: [a(.claude, "gzyms-site", .waits, "gzyms-site", "Claude needs your permission"), a(.claude, "notes", .idle, "notes")]),
        .tuios: AgentSourceLook(agents: [a(.tuios, "Fix login", .done, "web"), a(.tuios, "Orchestrator", .working, "gzyms")],
                                problem: "Agent features are off. Set agents.enabled = true in the config to use this command.", since: fixedNow),
    ]).item
    preview(PluginMenuView(rows: item.menu ?? []) { _, _ in }, "agents-popup")
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

@MainActor @Test func paletteShowsTheRowsThatFit() {
    let s = PaletteState()
    s.items = SettingsTab.allCases.map { PaletteItem(id: $0.rawValue, title: $0.title, kind: "Settings", words: $0.keywords) {} }
        + [PaletteItem(id: "dnd", title: "Do Not Disturb on", kind: "Action", words: "dnd") {}]
    s.query = "so"
    #expect(s.shown.first?.title == "Sounds")
    s.move(1)
    preview(PaletteView(state: s) { _ in }.themed(.mochaNeon), "palette")
    for q in ["agents", "tuios", "claude"] {
        s.query = q
        #expect(s.shown.first?.title == "Agents", "\(q)")
    }
    s.query = "zzz"
    #expect(s.shown.isEmpty && s.selected == 0)
    preview(PaletteView(state: s) { _ in }.themed(.mochaNeon), "palette-empty")
}

@Test func hintRowsCarryTheirActions() {
    let rows = ChordHints(snoozeMinutes: nil, hold: "⌃").rows(alt: "Open in agent", waiting: 2)
    #expect(rows.map { $0.map(\.text) } == [["⌃O open", "⌃X dismiss", "⌃Z snooze"], ["⌃A Open in agent"], ["⌃N next", "⌃P prev", "2 more"]])
    #expect(rows.flatMap { $0.map(\.action) } == [.open, .dismiss, .snooze(minutes: 3), .alt, .next, .previous, nil])
    #expect(ChordHints(snoozeMinutes: nil).rows(alt: nil).count == 1)  // no second action: no alt line
    #expect(ChordHints(snoozeMinutes: nil, note: "No second action").rows(alt: "x") == [[HintItem("No second action")]])
}

@Test func countSourceSaysWhoseNumberItIs() {
    #expect(CountSource(app: true, gzyms: false) == .app)
    #expect(CountSource(app: false, gzyms: true) == .gzyms)
    #expect(CountSource(app: true, gzyms: true) == .both)
    #expect(CountSource(app: false, gzyms: false) == nil)
    #expect(Set([CountSource.app, .gzyms, .both].map(\.fill)).count == 3)
    #expect(CountSource.text(app: "5", gzyms: 1) == "6")
    #expect(CountSource.text(app: "5", gzyms: 0) == "5")
    #expect(CountSource.text(app: "8", gzyms: 3) == "11")
    #expect(CountSource.text(app: "9223372036854775807", gzyms: 1) == "99+")
    #expect(CountSource.text(app: nil, gzyms: 12) == "12")  // the real number, as the app's
    #expect(CountSource.text(app: "98", gzyms: 5) == "99+")
    #expect(CountSource.text(app: "•", gzyms: 2) == "2")
    #expect(CountSource.text(app: "•", gzyms: 0) == "•")
    #expect(CountSource.text(app: "1K", gzyms: 2) == "1K")
}
