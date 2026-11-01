import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The settings panel: full width of the screen, unrolled from under the bar (spec: prototype v4).
/// Floats over other windows, so an app dragged from Finder can land on it, and stays when focus moves away.
/// Steps down to a normal window while something it opened (the app chooser, System Settings) is in use, and floats
/// again once clicked (Greg: the chooser must come over it). Closes on Esc, its ✕, a screen change, and Settings…
/// while it is in front.
@MainActor
final class SettingsPanel: NSPanel {
    var animate = true
    private var top: CGFloat = 0
    private var floor: CGFloat = 0
    /// One height for every tab (Greg: a panel that jumps between tabs is unpleasant); longer tabs scroll.
    private static let height: CGFloat = 640
    private var unrolling = false
    private let model: BarModel
    /// The setting j/k are on.
    let nav = SettingsNav()
    /// A shortcut recorder is listening: every key is its.
    var recording = false

    init(model: BarModel, actions: SettingsActions) {
        self.model = model
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SettingsRoot(model: model, actions: actions).environment(\.settingsNav, nav))
        // HyprMac tiles and frames every standard window; a floating one it leaves alone.
        setAccessibilitySubrole(.floatingWindow)
    }

    // Esc closes it, whatever inside has the focus (SwiftUI does not always pass it on as cancelOperation).
    // Otherwise h/l switch tabs, j/k walk the switches and menus, Enter or o flips one, unless a text field or a
    // recorder has the keys.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { super.sendEvent(event); return }
        let key = NavKey(keyCode: Int64(event.keyCode), modified: !event.modifierFlags.intersection([.command, .control, .option]).isEmpty)
        if key == .esc { hide(); return }
        if !recording, !nav.paused, !(firstResponder is NSText) {
            var keys = KeyNav(context: .settings, verbs: model.config.verbs)
            let r = keys.handle(.key(key), now: 0)
            for a in r.actions {
                switch a {
                case .move(let by): nav.move(by)
                case .choose: nav.choose()
                case .side(let by):
                    let all = SettingsTab.allCases
                    let i = all.firstIndex(of: model.settingsTab) ?? 0
                    model.settingsTab = all[min(max(i + by, 0), all.count - 1)]
                    nav.current = nil
                default: break
                }
            }
            if r.swallow { return }
        }
        super.sendEvent(event)
    }

    // Gzyms has no Edit menu, so ⌘V and friends never reach a text field on their own.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let edit: [String: Selector] = ["v": #selector(NSText.paste(_:)), "c": #selector(NSText.copy(_:)), "x": #selector(NSText.cut(_:)),
                                        "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:"))]
        if mods == .command, let key = event.charactersIgnoringModifiers?.lowercased(), let action = edit[key],
           NSApp.sendAction(action, to: nil, from: self) { return true }
        if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "z", NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // Text fields and the letter recorder need key focus; the app itself stays inactive.
    override var canBecomeKey: Bool { true }
    override func becomeKey() { super.becomeKey(); level = .floating }

    /// Before opening a window of another process over it.
    func stepBack() { level = .normal }
    override func cancelOperation(_ sender: Any?) { hide() }

    /// Visible and in front of other windows: Settings… then closes it; otherwise it brings it forward.
    var isInFront: Bool { isVisible && isKeyWindow }

    func show(on screen: NSScreen) {
        let f = screen.frame
        top = f.maxY - BarPanel.height
        floor = screen.visibleFrame.minY  // above the Dock when it shows
        let h = min(Self.height, top - floor)
        let rest = NSRect(x: f.minX, y: top - h, width: f.width, height: h)
        setFrame(animate ? NSRect(x: rest.minX, y: top - 1, width: rest.width, height: 1) : rest, display: false)
        alphaValue = 1
        model.settingsVisible = true
        makeKeyAndOrderFront(nil)
        guard animate else { return }
        unrolling = true
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.35
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)
            animator().setFrame(rest, display: true)
        } completionHandler: {
            // The content may have measured itself meanwhile: catch up with that height now.
            MainActor.assumeIsolated { self.unrolling = false }
        }
    }

    // Every way out (Esc, ✕, a screen change, the fold animation) ends here.
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        model.settingsVisible = false
    }

    /// The content reports its height on every tab change; the panel keeps its one height.
    func fit(height: CGFloat) {}

    func hide() {
        guard isVisible else { return }
        guard animate else { orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.2
            c.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(NSRect(x: frame.minX, y: top - 1, width: frame.width, height: 1), display: true)
        } completionHandler: {
            MainActor.assumeIsolated { if self.frame.height <= 1.5 { self.orderOut(nil) } }  // unless it was opened again meanwhile
        }
    }
}

/// Reads the bar's model, so a reload after each write redraws the panel with what the file now says.
private struct SettingsRoot: View {
    let model: BarModel
    let actions: SettingsActions

    var body: some View {
        SettingsView(tab: Binding(get: { model.settingsTab }, set: { model.settingsTab = $0 }), config: model.config,
                     problems: model.configProblems, broken: model.configBroken, apps: model.seenApps,
                     devices: model.audioDevices,
                     workspaceNames: Dictionary((model.stale ? [] : model.state?.workspaces ?? []).compactMap { w in w.name.map { (w.id, $0) } }) { a, _ in a },
                     grants: model.grants,
                     calendars: model.calendars,
                     logo: model.customLogo,
                     live: model.settingsVisible,
                     plugins: model.plugins,
                     actions: actions)
            .themed(model.config.theme)
            // Gzyms is never the active app, so AppKit would draw every switch greyed out as "inactive".
            .environment(\.controlActiveState, .key)
    }
}
