import AppKit
import GzymsCore
import SwiftUI

/// The grants with their state, a button to the right System Settings page and the Gzyms icon to drag onto its
/// list. Used by the Permissions tab and by the setup wizard.
public struct PermissionsView: View {
    let states: [GrantState]
    let open: (Grant) -> Void
    var restart: (() -> Void)?
    @Environment(\.theme) private var theme

    public init(states: [GrantState], open: @escaping (Grant) -> Void, restart: (() -> Void)? = nil) {
        self.states = states; self.open = open; self.restart = restart
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(states, id: \.grant) { s in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.grant.title)
                        Text(s.grant.why).font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    }
                    Spacer(minLength: 16)
                    // A running process keeps or lacks Full Disk Access until it restarts, whatever the switch says.
                    if s.grant == .fullDiskAccess, let restart { Button("Restart Gzyms", action: restart) }
                    if s.granted {
                        Label("granted", systemImage: "checkmark.circle.fill").foregroundStyle(theme[\.green])
                    } else {
                        Label("missing", systemImage: "xmark.circle.fill").foregroundStyle(theme[\.red])
                        AppIconToDrag()
                        Button("Open System Settings") { open(s.grant) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            if states.contains(where: { !$0.granted }) {
                Text("Drag the Gzyms icon into the list, or press + there and pick Gzyms in ~/Applications.")
                    .font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            ForEach([("Screen Recording", "only for screenshots in Report a problem"),
                     ("Camera and Microphone", "only for the check before a meeting")], id: \.0) { title, why in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                        Text(why).font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    }
                    Spacer()
                    Text("asked on first use").foregroundStyle(theme[\.overlay])
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }
}

/// The running app's own icon. Dropped on a System Settings privacy list it adds Gzyms, like dragging it from Finder.
private struct AppIconToDrag: View {
    @Environment(\.fileIcon) private var fileIcon
    var body: some View {
        Image(nsImage: fileIcon(Bundle.main.bundlePath))
            .resizable().frame(width: 30, height: 30)
            .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
            .help("Drag me into the list")
    }
}

/// The setup wizard's content: one line on why, the grants, and "Later".
public struct PermissionsWizardView: View {
    let states: [GrantState]
    let open: (Grant) -> Void
    let later: () -> Void
    @Environment(\.theme) private var theme

    public init(states: [GrantState], open: @escaping (Grant) -> Void, later: @escaping () -> Void) {
        self.states = states; self.open = open; self.later = later
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gzyms needs these to read app notifications and Dock badges. Each row updates as soon as you allow it.")
            PermissionsView(states: states, open: open)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme[\.surface].opacity(0.6)))
            HStack {
                Spacer()
                Button("Learn the keys in 5 min") { NSWorkspace.shared.open(tutorialURL) }
                Button(states.allSatisfy(\.granted) ? "Close" : "Later", action: later)
            }
        }
        .padding(18)
        .frame(width: 620)
        .foregroundStyle(theme[\.text])
        .background(theme[\.base])
    }
}
