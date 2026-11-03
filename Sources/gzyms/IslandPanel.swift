import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The banner's window: drops from the top edge, centred, so on a notch screen it reads as the notch growing down.
@MainActor
final class IslandPanel: NSPanel {
    var onOpen: () -> Void = {}
    var onRight: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    /// Scroll over the banner: +1 next, -1 previous.
    var onStep: (Int) -> Void = { _ in }
    /// A click on one of the banner's hints.
    var onHint: (ChordAction) -> Void = { _ in }
    /// The pointer is over the banner: its hints show as if the leader were held.
    private(set) var hovered = false
    /// The hint lit under the pointer: a click runs it instead of opening the banner.
    private var litHint: ChordAction?
    private var scrolled: CGFloat = 0
    /// A trackpad gesture's travel so far and the axis it locked to: across dismisses once, along steps.
    private var travel = CGPoint.zero
    private var swipe = Swipe.undecided
    private enum Swipe { case undecided, along, across, spent }
    private var lastScroll: TimeInterval = 0
    private var edges: CGFloat = 0
    private(set) var shown: GzymsNotification?
    private var inset: CGFloat = 0
    /// The edge the island hangs from (the notch or the bar's lower edge). It grows down from here and folds back
    /// into it, never above it: a monitor stacked on top would show it otherwise (Greg, 2026-10-31).
    private var top: CGFloat = 0
    /// Set when the icon flies to the bar: the island then fades where it is, so the eye follows one movement.
    var fadeNextHide = false
    /// `[appearance] animations` / Reduce motion: off = the island appears and goes without unrolling.
    var animate = true
    /// Where the app icon sits on screen, so it can fly from there to the bar.
    var avatarRect: NSRect { NSRect(x: frame.minX + 14, y: frame.midY + edges / 2 - (inset - 2) / 2 - 18, width: 36, height: 36) }
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)  // over the bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = host
        // The window's size is ours alone: SwiftUI pushing its own while the frame animates made the small
        // and the full island flicker over each other (Greg, 2026-10-31).
        host.sizingOptions = []
        host.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    /// A new notification while one is up swaps the content in place; only an empty island slides.
    /// Called again on hover, so the countdown restarts from the store's `remaining` or stands still.
    func show(_ n: GzymsNotification, icon: NSImage?, theme: Theme, on screen: NSScreen, total: Double?, remaining: Double?, running: Bool, hints: ChordHints?, queue: [GzymsNotification] = []) {
        let wasShown = shown != nil
        if shown?.id != n.id { log("island: show \(n.id)") }
        alphaValue = 1
        fadeNextHide = false  // a new banner took the place: nothing hides
        shown = n
        // With a notch the island grows out of it; without one it hangs from the bar's lower edge (Greg: no fake notch).
        let notch = screen.auxiliaryTopLeftArea != nil
        inset = notch ? screen.safeAreaInsets.top : 0
        let total = n.reminder ? nil : total
        edges = n.compact ? 0 : CGFloat(BannerView.edges(queue.count)) * (BannerView.edgeHeight + BannerView.edgeGap)
        let banner = BannerView(n: n, icon: icon, remaining: remaining, total: total, running: running, hints: hints, topInset: inset, queue: queue,
                                onHintHover: { [weak self] a, on in
                                    guard let self else { return }
                                    if on { litHint = a } else if litHint == a { litHint = nil }  // the next one may come first
                                })
            .themed(theme)
        let size = NSHostingView(rootView: banner).fittingSize
        // Centred at the top: while the window grows from the small island, it uncovers the full one from the middle.
        host.rootView = AnyView(banner.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        let f = screen.frame
        top = notch ? f.maxY : f.maxY - BarPanel.height
        let rest = NSRect(x: f.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        // A pending icon growing into the full banner (or any swap) animates like the prototype.
        guard animate else { setFrame(rest, display: true); orderFrontRegardless(); return }
        if wasShown { slide(to: rest, duration: 0.45, timing: CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.3, 1.1)); return }
        setFrame(folded(rest), display: false)
        orderFrontRegardless()
        // The prototype's entry: 0.35 s with a little overshoot, unrolling down from the edge.
        slide(to: rest, duration: 0.35, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.2))
    }

    func hide() {
        guard let gone = shown else { return }
        log("island: hide \(gone.id) (animate \(animate), fade \(fadeNextHide))")
        shown = nil
        hovered = false; litHint = nil  // gone from under the pointer: no exit event may come
        guard animate else {
            fadeNextHide = false
            // Out of the click's own event, like the animated path: an orderOut inside it can leave the window on screen.
            DispatchQueue.main.async { [weak self] in
                guard let self, shown == nil else { return }
                orderOut(nil)
            }
            return
        }
        if fadeNextHide {
            fadeNextHide = false
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.2
                animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    guard self.shown == nil else { self.alphaValue = 1; return }
                    self.orderOut(nil)
                    self.alphaValue = 1
                }
            }
            return
        }
        slide(to: folded(frame)) { [weak self] in
            guard let self, shown == nil else { return }
            orderOut(nil)
        }
    }

    /// The island rolled up into its edge: full width, one point tall.
    private func folded(_ r: NSRect) -> NSRect { NSRect(x: r.minX, y: top - 1, width: r.width, height: 1) }

    private func slide(to rect: NSRect, duration: Double = 0.18, timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeIn),
                       done: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { c in
            c.duration = duration
            c.timingFunction = timing
            animator().setFrame(rect, display: true)
        } completionHandler: { MainActor.assumeIsolated { done?() } }
    }

    // Clicks are taken here, before SwiftUI: left = open (or the hint under it), middle (wheel) = dismiss,
    // right or two fingers = the second action.
    // On the button's release: an orderOut while it is still held on this window leaves the window on screen.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: break
        case .leftMouseUp:
            if let a = litHint {
                log("island: hint \(a) on \(shown?.id ?? "nothing")")
                litHint = nil
                onHint(a)
                return
            }
            log("island: click on \(shown?.id ?? "nothing")"); onOpen()
        case .rightMouseUp: log("island: right click on \(shown?.id ?? "nothing")"); onRight()
        case .otherMouseUp where event.buttonNumber == 2: onDismiss()
        case .scrollWheel: scroll(event)
        default: super.sendEvent(event)
        }
    }

    /// A trackpad (events with a phase): each gesture locks to the axis it moved most along in its first few points.
    /// Vertical: one step per 40 pt of finger travel, so a long swipe goes further. Clearly sideways: dismiss once at 140 pt.
    /// The glide after the fingers lift never acts. A mouse wheel has no phase (Apple: legacy scroll events), even with
    /// precise deltas from smoothing (Logi sends 100+ pt per event): one step per turn, at most every 0.25 s, any size.
    /// Down = next, by the hand's movement (natural scrolling flips the sign).
    private func scroll(_ e: NSEvent) {
        let dy = e.scrollingDeltaY
        guard dy != 0 || !e.phase.isEmpty else { return }
        func step(_ dy: CGFloat) { onStep((e.isDirectionInvertedFromDevice ? dy > 0 : dy < 0) ? 1 : -1) }
        if e.phase.isEmpty {
            guard e.momentumPhase.isEmpty, e.timestamp - lastScroll >= 0.25 else { return }
            lastScroll = e.timestamp
            step(dy)
            return
        }
        if e.phase.contains(.began) || e.phase.contains(.mayBegin) { scrolled = 0; travel = .zero; swipe = .undecided }
        scrolled += dy
        travel.x += e.scrollingDeltaX; travel.y += dy
        if swipe == .undecided {
            guard max(abs(travel.x), abs(travel.y)) >= 10 else { return }
            swipe = abs(travel.x) > 2 * abs(travel.y) ? .across : .along
        }
        switch swipe {
        case .across:
            // A short flick must not throw one away unseen (Greg: 50 pt was too easy).
            guard abs(travel.x) >= 140 else { return }
            swipe = .spent
            log("island: swipe on \(shown?.id ?? "nothing")")
            onDismiss()
        case .along:
            guard abs(scrolled) >= 40 else { return }
            step(scrolled)
            scrolled = 0
        case .undecided, .spent: return
        }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; onHover(true) }
    override func mouseExited(with event: NSEvent) { hovered = false; onHover(false) }
}

/// The app icon flying from a hiding banner into its place on the bar (the prototype's "lot do ikony").
@MainActor
enum FlyToIcon {
    static func run(image: NSImage, from: NSRect, to target: NSRect, done: @escaping @MainActor () -> Void) {
        let p = NSPanel(contentRect: from, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        p.contentView = view
        p.orderFrontRegardless()
        let side = from.width * 0.3
        let end = NSRect(x: target.midX - side / 2, y: target.midY - side / 2, width: side, height: side)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.52
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.3, 1)
            p.animator().setFrame(end, display: true)
            p.animator().alphaValue = 0.6
        } completionHandler: {
            MainActor.assumeIsolated {
                p.orderOut(nil)
                done()
            }
        }
    }
}
