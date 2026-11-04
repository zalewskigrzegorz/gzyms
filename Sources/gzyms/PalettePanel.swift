import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The command palette's window: in the upper middle of the focused screen, takes the keys while up, closes on Esc,
/// after a row runs, and when focus moves away.
@MainActor
final class PalettePanel: NSPanel {
    let state = PaletteState()
    private let model: BarModel

    init(model: BarModel) {
        self.model = model
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setAccessibilitySubrole(.floatingWindow)  // HyprMac leaves floating windows alone
        contentView = NSHostingView(rootView: PaletteRoot(model: model, state: state, run: { [weak self] in self?.run($0) },
                                                          // Out of SwiftUI's layout pass: resizing the window inside it would lay out again.
                                                          resize: { s in DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.setContentSize(s) } } }))
    }

    override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); orderOut(nil) }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    // The panel, not the field, takes the arrows, Enter and Esc, so they work whatever SwiftUI does with them.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { super.sendEvent(event); return }
        switch event.keyCode {
        case 53: orderOut(nil)
        case 125: state.move(1)
        case 126: state.move(-1)
        case 36, 76: if let item = state.current { run(item, alt: event.modifierFlags.contains(.command)) }
        default: super.sendEvent(event)
        }
    }

    // Gzyms has no Edit menu, so ⌘V and friends never reach the field on their own.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let edit: [String: Selector] = ["v": #selector(NSText.paste(_:)), "c": #selector(NSText.copy(_:)), "x": #selector(NSText.cut(_:)),
                                        "a": #selector(NSText.selectAll(_:))]
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, let key = event.charactersIgnoringModifiers?.lowercased(),
           let action = edit[key], NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func show(items: [PaletteItem], extra: @escaping (String) -> [PaletteItem], on screen: NSScreen?) {
        state.items = items
        state.extra = extra
        state.query = ""
        guard let f = (screen ?? NSScreen.main)?.visibleFrame else { return }
        top = f.maxY - f.height * 0.2
        if let size = contentView?.fittingSize { setContentSize(size) }
        setFrameTopLeftPoint(NSPoint(x: f.midX - 280, y: top))
        makeKeyAndOrderFront(nil)
    }

    private var top: CGFloat = 0
    // The content sizes the window; its top edge stays put while the list grows and shrinks below it.
    override func setFrame(_ r: NSRect, display: Bool) {
        var r = r
        if top > 0 { r.origin.y = top - r.height }
        super.setFrame(r, display: display)
    }

    /// Closes first, so what the row opens (Settings, Sparkle) comes up in front.
    private func run(_ item: PaletteItem, alt: Bool = false) {
        orderOut(nil)
        (alt ? item.alt ?? item.run : item.run)()
    }
}

/// Reads the model, so the palette follows a theme change like Settings does.
private struct PaletteRoot: View {
    let model: BarModel
    let state: PaletteState
    let run: (PaletteItem) -> Void
    let resize: (CGSize) -> Void
    var body: some View {
        PaletteView(state: state, run: run, resize: resize)
            .themed(model.config.theme)
            .environment(\.controlActiveState, .key)
    }
}
