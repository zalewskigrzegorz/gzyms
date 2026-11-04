// Portions adapted from NotificationNanny (https://github.com/chessper53/NotificationNanny), MIT License, Copyright (c) 2026 chessper53
// (AXObserverController.swift, NotificationRepositioner.swift: scheduleHolds timing, hideOffscreen).
import AppKit
import ApplicationServices
import GzymsCore
import os

/// Another app's notification the moment its macOS banner shows (~100 ms; the database row comes ~5 s later):
/// an Accessibility observer on Notification Center reads the banner's text and parks the real banner off screen,
/// so only Gzyms's shows. The live element stays here for `NotificationClick` until the banner goes.
/// shortcut: rides on Notification Center's private Accessibility tree, a macOS update can break it;
/// then the database still delivers, a few seconds later.
/// Every Accessibility call runs on `queue`, never on the main thread: NC can stall for seconds after a wake, and
/// each call may wait up to the 1 s timeout. `queue` also owns the shared host window (banners and the panel live in
/// one fullscreen window), so parking for a banner and parking for a click never fight over it.
final class BannerSource: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.gzyms.banners")
    private let deliver: @MainActor (GzymsNotification) -> Void
    private let status = OSAllocatedUnfairLock(initialState: (attached: false, lastBanner: Date?.none))
    /// For Settings: the observer is attached / the last banner read. Any thread.
    var attached: Bool { status.withLock { $0.attached } }
    var lastBanner: Date? { status.withLock { $0.lastBanner } }

    // Everything below: `queue` only.
    private var running = false
    private(set) var nc: NCApp?
    private var observer: AXObserver?
    private var filter = BannerFilter()
    private var live: [String: AXUIElement] = [:]  // uuid, upper case with dashes → its banner
    /// The host window's own position while Gzyms keeps it off screen, one record for banners and clicks alike.
    private var host: (window: AXUIElement, home: CGPoint)?
    private var holdGeneration = 0
    private var restoreWork: DispatchWorkItem?
    private var attachWork: DispatchWorkItem?
    private var sweepWork: DispatchWorkItem?
    private var attachTries = 0
    /// A click runs through the panel: no sweep reads its rows, no restore moves its window.
    var pressing = false
    private var pidCheck: DispatchSourceTimer?

    init(deliver: @escaping @MainActor (GzymsNotification) -> Void) { self.deliver = deliver }

    private static var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// Idempotent. Without Accessibility or Notification Center, tries again every 10 s.
    func start() { queue.async { self.startOnQueue() } }

    /// Removes the observer and puts the parked window home.
    func stop() { queue.async { self.stopOnQueue() } }

    /// When Gzyms quits: waits until the window is home, so macOS's own banners are back.
    func stopNow() { queue.sync { self.stopOnQueue() } }

    /// An alert stays until closed: once Gzyms opened or dismissed it, its hidden original goes too.
    func closeParked(uuid: String) {
        queue.async {
            guard let el = self.live[uuid], el.subrole?.hasPrefix("AXNotificationCenterAlert") == true else { return }
            let closed = el.perform(anyOf: NCAX.closeNames)
            log("banners: alert \(uuid.prefix(8)) \(closed ? "closed" : "has no Close action")")
            if closed { self.live[uuid] = nil }
        }
    }

    /// `queue` only. The banner's element while it is up and the panel is closed; nil sends a click through the panel.
    func liveBanner(uuid: String) -> AXUIElement? {
        guard let el = live[uuid], let nc, !nc.panelOpen else { return nil }
        return el
    }

    /// `queue` only. Off screen at y −9999, remembering where it was unless it is already parked.
    func park(_ w: AXUIElement) {
        guard let p = w.point else { return }
        if host == nil || !CFEqual(host!.window, w) { if !NCAX.isParked(p) { host = (w, p) } }
        if !NCAX.isParked(p) { w.setPoint(CGPoint(x: p.x, y: NCAX.parkedY)) }
    }

    /// `queue` only. A click through the panel is over: the window goes home unless a banner still needs it parked.
    func pressDone() {
        pressing = false
        if live.isEmpty { restoreLater() }
    }

    private func startOnQueue() {
        guard !running else { return }
        running = true
        // NC is a background app: no didTerminate for it, and a killed NC sends no Accessibility event either
        // (live test 2026-11-04). Its pid changing is the sign it came back.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
        t.setEventHandler { [weak self] in
            guard let self, observer != nil else { return }
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: NCAX.bundleID).first?.processIdentifier
            if pid != nc?.pid { restarted() }
        }
        t.resume()
        pidCheck = t
        attach()
    }

    private func stopOnQueue() {
        guard running else { return }
        running = false
        pidCheck?.cancel()
        pidCheck = nil
        attachWork?.cancel()
        detach()
        restoreHome()
        log("banners: off")
    }

    private func attach() {
        guard running, observer == nil else { return }
        guard AXIsProcessTrusted(), let nc = NCApp.find() else { retryAttach(); return }
        // NC can take seconds to answer after a wake; fail fast instead of stalling.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        var obs: AXObserver?
        guard AXObserverCreate(nc.pid, bannerCallback, &obs) == .success, let obs else { retryAttach(); return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Since macOS 26 a banner raises no WindowCreated, only LayoutChanged or UIElementDestroyed.
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXWindowMovedNotification,
                  kAXMainWindowChangedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, nc.app, n as CFString, refcon)
        }
        // The source sits on the main run loop; its callback only hands the event to `queue`.
        nonisolated(unsafe) let source = AXObserverGetRunLoopSource(obs)
        DispatchQueue.main.async { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
        observer = obs
        self.nc = nc
        status.withLock { $0.attached = true }
        attachTries = 0
        // A window left parked by a Gzyms that died goes back to the top of the screen.
        for w in nc.windows { if let p = w.point, NCAX.isParked(p) { w.setPoint(CGPoint(x: p.x, y: 0)); log("banners: a parked window went home") } }
        // What is up already (a "Login Items" alert) is not ours: never published, never parked.
        filter.skipPresentAtStart.formUnion(nc.windows.flatMap { NCAX.banners(in: $0) }.compactMap { $0.identifier.flatMap(Self.key) })
        log("banners: on, \(filter.skipPresentAtStart.count) up already left alone")
    }

    private func detach() {
        if let observer {
            nonisolated(unsafe) let source = AXObserverGetRunLoopSource(observer)
            DispatchQueue.main.async { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        }
        observer = nil
        nc = nil
        status.withLock { $0.attached = false }
        live = [:]
        sweepWork?.cancel()
        sweepWork = nil
    }

    /// 1, 5, 15 s after Notification Center went away, then every 10 s like a missing grant.
    private func retryAttach() {
        guard running else { return }
        let delays = [1.0, 5, 15]
        let delay = attachTries < delays.count ? delays[attachTries] : 10
        attachTries += 1
        let work = DispatchWorkItem { [weak self] in self?.attach() }
        attachWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restarted() {
        guard running, observer != nil else { return }
        log("banners: Notification Center went away, attaching again")
        detach()
        host = nil  // its windows are gone with it
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
        // The panel's rows carry banner subroles too: while it is open, closing, or opened by a click, it is NC's.
        let open = pressing || nc.panelOpen
        filter.note(panelOpen: open, now: now)
        if open { holdGeneration += 1; return }
        var current = Set<String>(), notReady = false, held = false
        for w in nc.windows {
            for b in NCAX.banners(in: w) {
                guard let id = b.identifier.flatMap(Self.key) else { continue }
                current.insert(id)
                guard live[id] == nil, !filter.seen.contains(id), !filter.skipPresentAtStart.contains(id) else { continue }
                let lines = NCAX.read(b)
                if lines.title.isEmpty && lines.body.isEmpty { if filter.retry(uuid: id) { notReady = true }; continue }
                guard filter.accept(uuid: id, panelOpen: false, now: now) else { held = true; continue }
                live[id] = b
                parkHost(w)
                let app = Self.bundleID(named: lines.app)
                guard let n = bannerNotification(axIdentifier: id, lines: lines, app: app, at: Date()) else { continue }
                status.withLock { $0.lastBanner = Date() }
                log("banners: \(id.prefix(8)) from \(app ?? "an unknown app"), parked")
                let deliver = deliver
                DispatchQueue.main.async { MainActor.assumeIsolated { deliver(n) } }
            }
        }
        for id in live.keys where !current.contains(id) { live[id] = nil }
        // Text not there yet: again in 20 ms. Held back by the panel's close: again once the grace is over.
        if notReady || held { sweepLater(notReady ? 0.02 : BannerFilter.grace + 0.05) }
        if live.isEmpty, host != nil, restoreWork == nil { restoreLater() }
    }

    /// The running app with the banner's name, else an app of that name in /Applications or /System/Applications.
    private static func bundleID(named name: String) -> String? {
        guard !name.isEmpty else { return nil }
        if let id = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.bundleIdentifier { return id }
        for dir in ["/Applications", "/System/Applications"] {
            if let id = Bundle(path: "\(dir)/\(name).app")?.bundleIdentifier { return id }
        }
        return nil
    }

    private func sweepLater(_ delay: Double) {
        guard sweepWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.sweepWork = nil; self?.sweep() }
        sweepWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Parked now and again at 0.1/0.5/1/2 s: NC resets the position while it slides the banner in. A retry never
    /// moves the window while the panel is open or closing (that hid a closing panel in the spike, and NC then showed
    /// no banner until restarted); the panel opening also cancels every pending retry.
    private func parkHost(_ w: AXUIElement) {
        restoreWork?.cancel()
        restoreWork = nil
        park(w)
        let generation = holdGeneration
        for d in [0.1, 0.5, 1.0, 2.0] {
            queue.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self, generation == holdGeneration, !live.isEmpty, !pressing, let nc, let window = host?.window,
                      !filter.closing(now: Self.uptime), !nc.panelOpen else { return }
                park(window)
            }
        }
    }

    /// Home 1.5 s after the last banner went, never while the panel is open or a click uses it.
    private func restoreLater() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            restoreWork = nil
            guard live.isEmpty, !pressing else { return }
            if nc?.panelOpen == true { restoreLater() } else { restoreHome() }
        }
        restoreWork = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func restoreHome() {
        restoreWork?.cancel()
        restoreWork = nil
        guard let host else { return }
        host.window.setPoint(host.home)
        self.host = nil
        log("banners: host window back home")
    }
}

private func bannerCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let source = Unmanaged<BannerSource>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    nonisolated(unsafe) let element = element
    source.queue.async { source.event(element, name) }
}
