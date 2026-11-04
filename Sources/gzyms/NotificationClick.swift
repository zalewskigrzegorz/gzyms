// Portions adapted from NotificationNanny (https://github.com/chessper53/NotificationNanny), MIT License, Copyright (c) 2026 chessper53
// (NCPanelTakeover.swift: park after AXExpanded, keepInPlace, the 0.8 s close animation; NotificationRepositioner.swift: handleBannerTap).
import AppKit
import ApplicationServices

/// Opens another app's notification the way its own banner would, so the app gets its own data (the thread, the
/// chat, the event): Gzyms reads only the text, macOS hands that data to the sending app alone.
/// - Banner still up (parked by `BannerSource`): activate the app, press the banner.
/// - Banner gone: open Notification Center, wait for `AXExpanded`, only then park its host window off screen (NC puts
///   the window back while it opens, so parking earlier showed the panel), press the row with the record's uuid,
///   close the panel if NC did not, and let the window go home once NC has drawn its close.
/// The old trick parked before the panel opened, took the first window as the panel (since macOS 26 that can be a
/// banner, an alert or a widget) and never put it back.
/// Runs on `BannerSource.queue`, with the banners: never on the main thread, one click at a time, one owner of the window.
/// shortcut: rides on Notification Center's private Accessibility tree, the menu bar clock or globe+N, a macOS update
/// can break it; then `done(false)` and the caller opens the app as before.
enum NotificationClick {
    /// `uuid` as the panel names the banner (upper case, dashed). ≤ 2.5 s in all; `done` comes on the main thread.
    static func press(uuid: String, app: String?, via source: BannerSource, done: @escaping @MainActor @Sendable (Bool) -> Void) {
        source.queue.async {
            let finish: @Sendable (Bool) -> Void = { ok in DispatchQueue.main.async { MainActor.assumeIsolated { done(ok) } } }
            guard AXIsProcessTrusted(), !source.pressing else { finish(false); return }
            if let live = source.liveBanner(uuid: uuid) {
                let t0 = Date()
                if let app { activate(bundleID: app) }
                let r = live.press()
                log("nc click: banner \(uuid.prefix(8)) \(r == .success ? "pressed" : "press failed (\(r.rawValue)), trying the panel") \(ms(since: t0))")
                if r == .success { finish(true); return }
            }
            guard let nc = source.nc ?? NCApp.find() else { finish(false); return }
            PanelPress(source: source, nc: nc, uuid: uuid, app: app, done: finish).start()
        }
    }

    static func activate(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }

    static func ms(since t: Date) -> String { "\(Int(Date().timeIntervalSince(t) * 1000)) ms" }
}

/// The panel path, one step per turn of the banners' queue.
private final class PanelPress: @unchecked Sendable {
    let source: BannerSource, nc: NCApp, uuid: String, app: String?, done: @Sendable (Bool) -> Void
    let t0 = Date()
    var wasOpen = false, how = "already open"
    var host: AXUIElement?
    var stackPresses = 0, expandedAll = false, reparks = 0

    init(source: BannerSource, nc: NCApp, uuid: String, app: String?, done: @escaping @Sendable (Bool) -> Void) {
        self.source = source
        self.nc = nc
        self.uuid = uuid
        self.app = app
        self.done = done
    }

    var elapsed: Double { Date().timeIntervalSince(t0) }

    func after(_ s: Double, _ step: @escaping @Sendable () -> Void) { source.queue.asyncAfter(deadline: .now() + s, execute: step) }

    func start() {
        source.pressing = true
        wasOpen = nc.panelOpen  // the user's own panel stays where it is
        if !wasOpen { how = NCAX.toggle() }
        waitOpen()
    }

    func waitOpen() {
        guard nc.panelOpen else {
            if elapsed > 1.5 { log("nc click: Notification Center did not open via \(how) (is the globe+N shortcut on?)"); finish(false); return }
            after(0.005) { self.waitOpen() }
            return
        }
        if !wasOpen, let h = nc.host {
            host = h
            source.park(h)
        }
        find()
    }

    func find() {
        if let host, let p = host.point, !NCAX.isParked(p) {
            source.park(host)  // NC can move it back while it lays the panel out
            reparks += 1
        }
        guard elapsed < 2.5 else {
            log("nc click: \(uuid.prefix(8)) is not in Notification Center (its box off for that app?) after \(NotificationClick.ms(since: t0))")
            finish(false)
            return
        }
        let w = host ?? nc.host
        if let w, let hit = NCAX.find(in: w, id: uuid) {
            // A collapsed stack carries its newest notification's id; a press opens it, then the row is there.
            if hit.subrole?.hasSuffix("Stack") == true, stackPresses < 2 {
                hit.press()
                stackPresses += 1
                after(0.15) { self.find() }
                return
            }
            pressRow(hit)
            return
        }
        if let w, !expandedAll {
            expandedAll = true
            NCAX.all(in: w).filter { $0.subrole?.hasSuffix("Stack") == true }.forEach { $0.press() }
        }
        after(0.02) { self.find() }
    }

    func pressRow(_ row: AXUIElement) {
        if let app { NotificationClick.activate(bundleID: app) }
        else { let name = NCAX.read(row).app; NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.activate() }
        let r = row.press()
        log("nc click: panel \(r == .success ? "row pressed" : "press failed (\(r.rawValue))") via \(how), \(reparks) re-parks, "
            + "\(stackPresses) stack presses, \(NotificationClick.ms(since: t0))")
        finish(r == .success)
    }

    /// Closes the panel this opened (unless NC did, within 0.3 s); the window goes home after NC's close animation.
    func finish(_ ok: Bool) {
        done(ok)
        guard !wasOpen else { source.pressDone(); return }
        after(0.3) {
            if self.nc.panelOpen { _ = NCAX.toggle(prefer: self.how) }
            self.after(0.8) { self.source.pressDone() }
        }
    }
}
