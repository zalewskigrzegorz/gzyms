import AppKit
import GzymsCore
import GzymsUI
import SwiftUI

/// Settings → Apps, step by step: floats at the right edge, beside System Settings, while `model.appSetup` runs.
@MainActor
final class AppSetupPanel: NSPanel {
    init(model: BarModel, skip: @escaping () -> Void, stop: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 520), styleMask: [.titled, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Set up apps"
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setAccessibilitySubrole(.floatingWindow)  // HyprMac leaves floating windows alone
        let host = NSHostingView(rootView: SetupView(model: model, skip: skip, stop: stop))
        host.sizingOptions = [.preferredContentSize]
        contentView = host
    }

    func show(on screen: NSScreen?) {
        if let f = screen?.visibleFrame { setFrameOrigin(NSPoint(x: f.maxX - frame.width - 24, y: f.midY - frame.height / 2)) }
        orderFrontRegardless()
    }
}

/// Reads the model so each second's read of macOS redraws the mirror.
private struct SetupView: View {
    let model: BarModel
    let skip: () -> Void, stop: () -> Void
    var body: some View {
        if let s = model.appSetup {
            let id = s.queue[s.at]
            AppSetupView(app: model.seenApps.first { $0.id == id } ?? SeenApp(id: id, name: id, icon: nil),
                         step: s.at + 1, total: s.queue.count, skip: skip, stop: stop)
                .themed(model.config.theme)
                .environment(\.controlActiveState, .key)
        }
    }
}
