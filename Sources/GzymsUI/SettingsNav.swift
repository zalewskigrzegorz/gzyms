import Observation
import SwiftUI

/// The setting the keyboard is on in the Settings panel (j/k move, Enter flips). Switches and menus put themselves
/// here as they draw; the order is column by column, top to bottom, as the eye reads the tab.
@Observable @MainActor
public final class SettingsNav {
    public var current: UUID?
    /// A letter recorder listens: every key is its.
    @ObservationIgnored public var paused = false
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    @ObservationIgnored var chooses: [UUID: () -> Void] = [:]

    nonisolated public init() {}

    /// The controls sit at their row's right edge, so one column shares one right edge.
    private var order: [UUID] {
        frames.sorted { a, b in
            let ca = (a.value.maxX / 100).rounded(), cb = (b.value.maxX / 100).rounded()
            return ca != cb ? ca < cb : a.value.minY < b.value.minY
        }.map(\.key)
    }

    public func move(_ by: Int) {
        let o = order
        guard !o.isEmpty else { return }
        guard let c = current, let i = o.firstIndex(of: c) else { current = by > 0 ? o.first : o.last; return }
        current = o[min(max(i + by, 0), o.count - 1)]
    }

    public func choose() { if let c = current { chooses[c]?() } }

    fileprivate func forget(_ id: UUID) {
        frames[id] = nil; chooses[id] = nil
        if current == id { current = nil }
    }
}

extension EnvironmentValues {
    /// Set by the Settings panel; nil elsewhere (pictures, previews), where nothing registers.
    @Entry public var settingsNav: SettingsNav?
}

/// A control the keyboard can land on in Settings: Enter runs `choose`, the highlight shows where j/k are.
struct SettingsSlot: ViewModifier {
    let choose: () -> Void
    @State private var me = UUID()
    @Environment(\.settingsNav) private var nav
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        // Kept fresh on every draw: a switch's choose flips the value it has now, not the one it first drew with.
        let _ = nav?.chooses[me] = choose
        content
            // Drawn around the control, not padded into it: the rows keep their layout.
            .background { if nav?.current == me { RoundedRectangle(cornerRadius: 6).fill(theme[\.gold].opacity(0.35)).padding(-4) } }
            .id(me)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { nav?.frames[me] = $0 }
            .onDisappear { nav?.forget(me) }
    }
}

extension View {
    func settingsSlot(choose: @escaping () -> Void) -> some View { modifier(SettingsSlot(choose: choose)) }
}

/// Every plain button in Settings is a place for j/k too; Enter presses it.
struct SlotButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.automatic).settingsSlot { configuration.trigger() }
    }
}
