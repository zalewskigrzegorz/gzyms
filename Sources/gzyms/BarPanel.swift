import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The one window per screen. Everything on the bar is drawn inside it; it is created once and only resized.
@MainActor
final class BarPanel: NSPanel {
    static let height: CGFloat = 36
    private let model: BarModel
    private let host: NSHostingView<PanelRoot>
    private var home = NSRect.zero  // the screen this bar sits on
    private var yield = MenuBarYield()
    private var poll: Timer?
    /// App icons (and "bell") in this panel, in SwiftUI's top-left window coordinates.
    private var iconFrames: [String: CGRect] = [:]
    /// This bar's open popup and keyboard row.
    let popups = PopupState()
    /// What the keyboard mode's hints can point at on this bar, by id.
    private(set) var spots: [String: HintSpot] = [:]
    var onSpots: () -> Void = {}

    init(screen: NSScreen, model: BarModel) {
        self.model = model
        host = NSHostingView(rootView: PanelRoot(model: model, notch: nil))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar  // above the revealed system menu: Greg does not use the macOS menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = host
        host.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        fit(to: screen)
        orderFrontRegardless()
    }

    func fit(to screen: NSScreen) {
        let f = screen.frame
        home = f
        yield = MenuBarYield()
        ignoresMouseEvents = false
        setFrame(NSRect(x: f.minX, y: f.maxY - Self.height, width: f.width, height: Self.height), display: true)
        // The background runs under the notch (it is black anyway); only content keeps out of it.
        host.rootView = PanelRoot(model: model, notch: Self.notchGap(on: screen), popups: popups, panel: ObjectIdentifier(self),
                                  // Room for the bar, a popup's header, padding and arrow, and a gap above the Dock.
                                  popupMaxHeight: screen.visibleFrame.height - 120,
                                  onHint: { [weak self] id, spot in self?.spots[id] = spot; self?.onSpots() }) { [weak self] id, r in self?.iconFrames[id] = r }
    }

    // MARK: - Stepping aside for the macOS menu bar (hold `[bar] menu_bar_key`, ⌘ by default, on the bar)

    // The pointer and ⌘ are polled only while the pointer is on the bar or the bar is away: ~0% otherwise.
    override func mouseEntered(with event: NSEvent) {
        guard poll == nil, model.config.menuBarKey != .off else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private func tick() {
        let p = NSEvent.mouseLocation
        // The menu bar is taller than the bar on a notch screen.
        let strip = max(Self.height, NSScreen.screens.first { $0.frame == home }?.safeAreaInsets.top ?? 0)
        let inStrip = p.x >= home.minX && p.x < home.maxX && p.y >= home.maxY - strip
        // The key alone: ⌘⇧ (screenshots), ⌘⌥ and friends belong to other shortcuts.
        let want: NSEvent.ModifierFlags = switch model.config.menuBarKey {
        case .cmd: .command
        case .ctrl: .control
        case .alt: .option
        case .shift: .shift
        case .off: []
        }
        let keyOnly = !want.isEmpty && NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]) == want
        if yield.update(now: ProcessInfo.processInfo.systemUptime, inStrip: inStrip, command: keyOnly) {
            slide(away: yield.yielded)
        }
        if !inStrip && !yield.yielded { poll?.invalidate(); poll = nil }
    }

    /// Slides up off the screen, so the menu bar that macOS shows at the top edge is free to click.
    private func slide(away: Bool) {
        let rest = NSRect(x: home.minX, y: home.maxY - Self.height, width: home.width, height: Self.height)
        ignoresMouseEvents = away
        if away { popups.open = nil }
        log("menu bar: \(away ? "yield" : "back")")
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            c.timingFunction = CAMediaTimingFunction(name: away ? .easeIn : .easeOut)
            animator().setFrame(away ? rest.offsetBy(dx: 0, dy: Self.height) : rest, display: true)
        }
    }

    var screenFrame: NSRect { home }

    /// Left to right, only what is on the bar's width (the left side clips what runs into the notch).
    func hintTargets() -> [HintTarget] {
        spots.values.filter { $0.frame.minX >= 0 && $0.frame.maxX <= frame.width }.sorted { $0.frame.minX < $1.frame.minX }.map(\.target)
    }

    /// An icon's place in screen coordinates; nil when this panel does not show it.
    func iconRect(_ id: String) -> NSRect? {
        guard let r = iconFrames[id] else { return nil }
        return NSRect(x: frame.minX + r.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
    }

    private static func notchGap(on screen: NSScreen) -> NotchGap? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return NotchGap(screenWidth: screen.frame.width, leftAreaWidth: left.width, rightAreaWidth: right.width)
    }
}
