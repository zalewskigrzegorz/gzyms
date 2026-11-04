// Portions adapted from NotificationNanny (https://github.com/chessper53/NotificationNanny), MIT License, Copyright (c) 2026 chessper53
// (AXObserverController.swift, NotificationRepositioner.swift: scheduleHolds timing, hideOffscreen).
import AppKit
import ApplicationServices
import GzymsCore

/// Another app's notification the moment its macOS banner shows (~100 ms; the database row comes ~5 s later):
/// an Accessibility observer on Notification Center reads the banner's text and parks the real banner off screen,
/// so only Gzyms's shows. The live element stays here for `NotificationClick` until the banner goes.
/// shortcut: rides on Notification Center's private Accessibility tree, a macOS update can break it;
/// then the database still delivers, a few seconds later.
/// All of it runs on the main thread, where the observer's run loop source lives; NC answers within the 1 s timeout.
@MainActor
final class BannerSource {
    private let deliver: @MainActor (GzymsNotification) -> Void
    /// Parking on: the real banner goes off screen. Off: it stays where macOS put it, the text is still read.
    var park = true { didSet { if !park { restoreHomes() } } }
    private(set) var attached = false
    private(set) var lastBanner: Date?
    private var running = false
    private var nc: NCApp?
    private var observer: AXObserver?
    private var filter = BannerFilter()
    private var live: [String: AXUIElement] = [:]  // uuid, upper case with dashes → its banner
    private var homes: [(AXUIElement, CGPoint)] = []
    private var restoreWork: DispatchWorkItem?
    private var attachWork: DispatchWorkItem?
    private var sweepWork: DispatchWorkItem?
    private var attachTries = 0
    private var terminateObserver: NSObjectProtocol?

    init(deliver: @escaping @MainActor (GzymsNotification) -> Void) { self.deliver = deliver }

    private static var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// Idempotent. Without Accessibility or Notification Center, tries again every 10 s.
    func start() {
        guard !running else { return }
        running = true
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { [weak self] in if id == NCAX.bundleID { self?.restarted() } }
        }
        attach()
    }

    /// Removes the observer and puts every parked window home.
    func stop() {
        guard running else { return }
        running = false
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
        terminateObserver = nil
        attachWork?.cancel()
        detach()
        restoreHomes()
        log("banners: off")
    }

    /// The banner's element while it is up and the panel is closed; nil sends a click through the panel.
    func liveBanner(uuid: String) -> AXUIElement? {
        guard let el = live[uuid], let nc, !nc.panelOpen else { return nil }
        return el
    }

    /// An alert stays until closed: once Gzyms opened or dismissed it, its hidden original goes too.
    func closeParked(uuid: String) {
        guard let el = live[uuid], el.subrole?.hasPrefix("AXNotificationCenterAlert") == true else { return }
        let closed = el.perform(anyOf: NCAX.closeNames)
        log("banners: alert \(uuid.prefix(8)) \(closed ? "closed" : "has no Close action")")
        if closed { live[uuid] = nil }
    }

    private func attach() {
        guard running, observer == nil else { return }
        guard AXIsProcessTrusted(), let nc = NCApp.find() else { retryAttach(); return }
        // NC can take seconds to answer after a wake; fail fast instead of stalling the bar.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        var obs: AXObserver?
        guard AXObserverCreate(nc.pid, bannerCallback, &obs) == .success, let obs else { retryAttach(); return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Since macOS 26 a banner raises no WindowCreated, only LayoutChanged or UIElementDestroyed.
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXWindowMovedNotification,
                  kAXMainWindowChangedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, nc.app, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        self.nc = nc
        attached = true
        attachTries = 0
        // A window left parked by a Gzyms that died goes back to the top of the screen.
        for w in nc.windows { if let p = w.point, NCAX.isParked(p) { w.setPoint(CGPoint(x: p.x, y: 0)); log("banners: a parked window went home") } }
        // What is up already (a "Login Items" alert) is not ours: never published, never parked.
        filter.skipPresentAtStart = Set(nc.windows.flatMap { NCAX.banners(in: $0) }.compactMap { $0.identifier.flatMap(Self.key) })
        log("banners: on, \(filter.skipPresentAtStart.count) up already left alone")
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        nc = nil
        attached = false
        live = [:]
        sweepWork?.cancel()
    }

    /// 1, 5, 15 s after Notification Center went away, then every 10 s like a missing grant.
    private func retryAttach() {
        guard running else { return }
        let delays = [1.0, 5, 15]
        let delay = attachTries < delays.count ? delays[attachTries] : 10
        attachTries += 1
        let work = DispatchWorkItem { [weak self] in self?.attach() }
        attachWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restarted() {
        guard running, attached else { return }
        log("banners: Notification Center went away, attaching again")
        detach()
        homes = []  // its windows are gone with it
        attachTries = 0
        retryAttach()
    }

    fileprivate func event(_ element: AXUIElement, _ name: String) {
        if name == kAXUIElementDestroyedNotification, let nc, CFEqual(element, nc.app) { restarted(); return }
        sweep()
    }

    private static func key(_ identifier: String) -> String? { UUID(uuidString: identifier)?.uuidString }

    private func sweep() {
        guard let nc else { return }
        let now = Self.uptime
        let open = nc.panelOpen
        filter.note(panelOpen: open, now: now)
        // The panel's rows carry banner subroles too: while it is open, and while it closes, it is NC's.
        guard !open else { return }
        var current = Set<String>(), notReady = false, held = false
        for w in nc.windows {
            for b in NCAX.banners(in: w) {
                guard let id = b.identifier.flatMap(Self.key) else { continue }
                current.insert(id)
                guard live[id] == nil, !filter.seen.contains(id), !filter.skipPresentAtStart.contains(id) else { continue }
                let lines = NCAX.read(b)
                if lines.title.isEmpty && lines.body.isEmpty { notReady = true; continue }
                guard filter.accept(uuid: id, panelOpen: false, now: now) else { held = true; continue }
                live[id] = b
                if park { parkHost(w) }
                let app = NSWorkspace.shared.runningApplications.first { $0.localizedName == lines.app }?.bundleIdentifier
                guard let n = bannerNotification(axIdentifier: id, lines: lines, app: app, at: Date()) else { continue }
                lastBanner = Date()
                log("banners: \(id.prefix(8)) from \(app ?? "an unknown app")\(park ? ", parked" : "")")
                deliver(n)
            }
        }
        for id in live.keys where !current.contains(id) { live[id] = nil }
        // Text not there yet: again in 20 ms. Held back by the panel's close: again once the grace is over.
        if notReady || held { sweepLater(notReady ? 0.02 : BannerFilter.grace + 0.05) }
        if live.isEmpty, !homes.isEmpty, restoreWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                restoreWork = nil
                if live.isEmpty { restoreHomes() }
            }
            restoreWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    private func sweepLater(_ delay: Double) {
        guard sweepWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.sweepWork = nil; self?.sweep() }
        sweepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Off screen at y −9999, again at 0.1/0.5/1/2 s: NC resets the position while it slides the banner in.
    /// A write can report success and still be refused, so each hold reads the position first.
    private func parkHost(_ w: AXUIElement) {
        restoreWork?.cancel()
        restoreWork = nil
        if let p = w.point, !NCAX.isParked(p), !homes.contains(where: { CFEqual($0.0, w) }) { homes.append((w, p)) }
        let hold: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, park, !live.isEmpty, let nc, !nc.panelOpen, let p = w.point, !NCAX.isParked(p) else { return }
            w.setPoint(CGPoint(x: p.x, y: NCAX.parkedY))
        }
        hold()
        for d in [0.1, 0.5, 1.0, 2.0] { DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: hold) }
    }

    private func restoreHomes() {
        restoreWork?.cancel()
        restoreWork = nil
        for (w, p) in homes { w.setPoint(p) }
        if !homes.isEmpty { log("banners: host window back home") }
        homes = []
    }
}

private func bannerCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let source = Unmanaged<BannerSource>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    nonisolated(unsafe) let element = element  // the observer's source is on the main run loop: this is the main thread
    MainActor.assumeIsolated { source.event(element, name) }
}
