import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// The one separate window (spec): opens at launch when a grant is missing, from the bar's ⚠ and from the logo menu.
/// Closes itself once everything is granted; "Later" closes it until the next launch.
@MainActor
final class PermissionsWizard: NSPanel {
    init(model: BarModel, open: @escaping (Grant) -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 360), styleMask: [.titled, .closable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Set up Gzyms"
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setAccessibilitySubrole(.floatingWindow)  // HyprMac leaves floating windows alone
        contentView = NSHostingView(rootView: WizardView(model: model, open: open, later: { [weak self] in self?.orderOut(nil) }))
    }

    override var canBecomeKey: Bool { true }

    func show(on screen: NSScreen?) {
        level = .floating
        if let f = screen?.visibleFrame { setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2)) }
        makeKeyAndOrderFront(nil)
    }

    /// System Settings must come over it while the user drags the icon there.
    func stepBack() { level = .normal }
}

/// Reads the model so each check redraws the rows.
private struct WizardView: View {
    let model: BarModel
    let open: (Grant) -> Void
    let later: () -> Void
    var body: some View {
        PermissionsWizardView(states: model.grants, open: open, later: later)
            .themed(model.config.theme)
            .environment(\.controlActiveState, .key)
    }
}
