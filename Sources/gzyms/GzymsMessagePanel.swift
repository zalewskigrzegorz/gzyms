import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The window of a message from Gzyms (GzymsMessageView). Several wait in line and come one after another.
@MainActor
final class GzymsMessagePanel: NSPanel {
    private var queue: [GzymsMessageView] = []
    private let model: BarModel

    init(model: BarModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setAccessibilitySubrole(.floatingWindow)  // HyprMac leaves floating windows alone
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { next() }

    func show(_ view: GzymsMessageView, on screen: NSScreen?) {
        queue.append(view)
        if queue.count == 1 { present(on: screen) }
    }

    /// Closes the one on screen and brings the next, if any.
    func next() {
        if !queue.isEmpty { queue.removeFirst() }
        if queue.isEmpty { orderOut(nil) } else { present(on: screen) }
    }

    private func present(on screen: NSScreen?) {
        guard let m = queue.first else { return }
        let host = NSHostingView(rootView: MessageRoot(model: model, view: m))
        contentView = host
        setContentSize(host.fittingSize)
        // A bit above the middle, so it does not sit right on the setup wizard.
        if let f = (screen ?? NSScreen.main)?.visibleFrame { setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY + 40)) }
        makeKeyAndOrderFront(nil)
        invalidateShadow()  // the shadow follows the rounded corners, not the square window
    }
}

/// Reads the model, so the message follows a theme change like Settings does.
private struct MessageRoot: View {
    let model: BarModel
    let view: GzymsMessageView
    var body: some View {
        view.themed(model.config.theme)
            // Gzyms is never the active app, so AppKit would draw its controls as "inactive".
            .environment(\.controlActiveState, .key)
    }
}
