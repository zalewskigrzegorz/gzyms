import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The armageddon on every screen, over everything (full-screen apps too), with a sound every 1.5 s until clicked.
/// Another notification does not replace it: it stays until the user acts on it.
@MainActor
final class ArmageddonController {
    var onOpen: (String) -> Void = { _ in }
    var onDismiss: (String) -> Void = { _ in }
    /// On screen or gone: the keyboard takes Enter for it only while it is up.
    var onVisible: (Bool) -> Void = { _ in }
    private(set) var shown: GzymsNotification?
    private var panels: [ArmageddonPanel] = []
    private var sound: Timer?

    /// A new one replaces the one on screen; the same id only refreshes the text.
    func show(_ n: GzymsNotification, theme: Theme, calm: Bool) {
        let fresh = shown?.id != n.id
        shown = n
        onVisible(true)
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let p = ArmageddonPanel(frame: screen.frame)
            p.contentView = NSHostingView(rootView: ArmageddonView(n: n, icon: n.app.flatMap(AppIcons.icon(for:)), calm: calm)
                .themed(theme))
            p.onLeft = { [weak self] in self?.act(open: true) }
            p.onRight = { [weak self] in self?.act(open: false) }
            p.orderFrontRegardless()
            return p
        }
        guard fresh || sound == nil else { return }
        // Plays whatever the sound switch and Focus say: an armageddon is meant to be heard.
        // shortcut: always Sosumi, a sound picker in the settings can come later.
        beep()
        sound?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { _ in MainActor.assumeIsolated { [weak self] in self?.beep() } }
        RunLoop.main.add(t, forMode: .common)
        sound = t
    }

    /// Screens came or went: the same armageddon on the new set.
    func screensChanged(theme: Theme, calm: Bool) {
        if let n = shown { show(n, theme: theme, calm: calm) }
    }

    func hide() {
        sound?.invalidate(); sound = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        shown = nil
        onVisible(false)
    }

    /// From the keyboard (Enter or the open letter).
    func open() { act(open: true) }

    private func act(open: Bool) {
        guard let id = shown?.id else { return }
        hide()
        if open { onOpen(id) } else { onDismiss(id) }
    }

    /// The armageddon sound from `[sounds]`; set by the app delegate.
    var playSound: () -> Void = {}

    private func beep() { playSound() }
}

private final class ArmageddonPanel: NSPanel {
    var onLeft: () -> Void = {}
    var onRight: () -> Void = {}

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(frame, display: false)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: onLeft()
        case .rightMouseDown: onRight()
        default: super.sendEvent(event)
        }
    }
}
