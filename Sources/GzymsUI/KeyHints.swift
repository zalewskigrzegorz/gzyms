import GzymsCore
import SwiftUI

/// Something a hint can point at, where it sits in its panel, and what a hint does to an action target.
public struct HintSpot {
    public var target: HintTarget
    public var frame: CGRect
    public var action: (() -> Void)?
}

/// A hint as drawn: its letters over a target's frame.
public struct HintLabel: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    public init(text: String, frame: CGRect) { self.text = text; self.frame = frame }
}

extension EnvironmentValues {
    /// Where hint targets report themselves; nil spot = gone.
    @Entry public var reportHint: (String, HintSpot?) -> Void = { _, _ in }
}

struct HintTargetModifier: ViewModifier {
    let id: String?
    let popup: Bool
    let action: (() -> Void)?
    @State private var frame = CGRect.zero
    @Environment(\.reportHint) private var report

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0; send() }
            .onChange(of: id) { old, _ in if let old { report(old, nil) }; send() }
            .onChange(of: popup) { send() }
            .onDisappear { if let id { report(id, nil) } }
    }

    private func send() {
        guard let id else { return }
        report(id, frame.isEmpty ? nil : HintSpot(target: HintTarget(id: id, popup: popup), frame: frame, action: action))
    }
}

extension View {
    /// A target for the keyboard mode's hints. `popup` = the hint opens the popup with this id; otherwise it runs
    /// `action`. A nil id is no target (an app icon without notifications: its workspace's hint covers it).
    public func hintTarget(_ id: String?, popup: Bool, action: (() -> Void)? = nil) -> some View {
        modifier(HintTargetModifier(id: id, popup: popup, action: action))
    }
}

/// The keyboard mode on this bar: a gold edge and the hints over their targets. Letters already typed fade.
public struct HintOverlay: View {
    let labels: [HintLabel]
    let typed: String
    @Environment(\.theme) private var theme
    public init(labels: [HintLabel], typed: String) { self.labels = labels; self.typed = typed }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).strokeBorder(theme[\.gold], lineWidth: 2)
            ForEach(labels.filter { $0.text.hasPrefix(typed) }, id: \.text) { l in
                (Text(typed).foregroundStyle(theme[\.base].opacity(0.45)) + Text(l.text.dropFirst(typed.count)).foregroundStyle(theme[\.base]))
                    .font(.system(size: 11, weight: .heavy).monospaced())
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(theme[\.gold], in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    .position(x: l.frame.midX, y: l.frame.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
