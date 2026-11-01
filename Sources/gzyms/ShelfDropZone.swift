import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// While a file is dragged in any other app, a drop place hangs under the notch (or the bar) of the screen under the
/// pointer, so the shelf is found without aiming at a pill (Greg, 2026-10-31). A drag shows up as a new write to the
/// drag pasteboard during a mouse drag; the zone goes once the button is up.
@MainActor
final class ShelfDropZone {
    var enabled: () -> Bool = { true }
    var theme: () -> Theme = { .mochaNeon }
    var animate: () -> Bool = { true }
    var onDrop: ([URL]) -> Void = { _ in }
    private var monitor: Any?
    private var seen = NSPasteboard(name: .drag).changeCount
    private var screen: NSRect?
    private var watch: Timer?
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)  // over the bar, like the banner
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        return p
    }()

    func start() {
        // Mouse events need no permission here, only keys would. Our own drags (out of the shelf) never reach it.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }
    }

    private func dragged() {
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != seen else { return }
        seen = pb.changeCount
        guard enabled(), pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        place()
        watch?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        watch = t
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            watch?.invalidate(); watch = nil
            // The drop lands after the button is up: give it a moment before the zone goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in MainActor.assumeIsolated { self?.hide() } }
            return
        }
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), s.frame != screen { place(on: s) }
    }

    private func place(on target: NSScreen? = nil) {
        let mouse = NSEvent.mouseLocation
        guard let s = target ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let first = screen == nil
        screen = s.frame
        let notch = s.auxiliaryTopLeftArea != nil
        let inset = notch ? s.safeAreaInsets.top : 0
        let top = notch ? s.frame.maxY : s.frame.maxY - BarPanel.height
        let size = NSSize(width: 340, height: inset + 96)
        panel.contentView = NSHostingView(rootView: ShelfDropZoneView(topInset: inset) { [weak self] files in
            self?.onDrop(files)
            self?.hide()
        }.themed(theme()))
        let rest = NSRect(x: s.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        guard first, animate() else { panel.setFrame(rest, display: true); panel.orderFrontRegardless(); return }
        // Unrolls down from its edge, like the banner island.
        panel.setFrame(NSRect(x: rest.minX, y: top - 1, width: rest.width, height: 1), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.2)
            panel.animator().setFrame(rest, display: true)
        }
    }

    private func hide() {
        guard screen != nil else { return }
        screen = nil
        panel.orderOut(nil)
    }
}
