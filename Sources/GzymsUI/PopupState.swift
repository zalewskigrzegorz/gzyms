import Observation
import SwiftUI

/// Which popup of one bar is open and which of its rows the keyboard is on. One per panel, so a pill's popup opens
/// on the screen it was asked on. Mouse and keyboard both go through it.
@Observable @MainActor
public final class PopupState {
    /// The target id: "widget:audio", "app:<bundle id>", "bell", "plugin:<folder>:<key>".
    public var open: String? { didSet { if open != oldValue { row = 0 } } }
    public var row = 0
    /// A row that was asked for a second action it does not have; it says so for a moment.
    public private(set) var noAlt: Int?
    /// What Enter and x do on each row, by index. Filled by the rows of the open popup as they draw.
    @ObservationIgnored public var rows: [Int: Row] = [:]

    public struct Row {
        var owner: UUID
        public var choose: () -> Void
        public var remove: (() -> Void)?
        public var alt: (() -> Void)?
    }

    nonisolated public init() {}

    public func binding(_ id: String) -> Binding<Bool> {
        Binding { self.open == id } set: { on in
            if on { self.open = id } else if self.open == id { self.open = nil }
        }
    }

    /// Stays on the list: a list that got shorter under it lands on its last row.
    public func move(_ by: Int) {
        let count = rows.keys.max().map { $0 + 1 } ?? 0
        row = count == 0 ? 0 : min(max(row + by, 0), count - 1)
    }

    public func choose() { rows[row]?.choose() }
    /// true = the row had a second action and ran it; otherwise the row shows "No second action".
    public func alt() -> Bool {
        if let a = rows[row]?.alt { a(); return true }
        let r = row
        noAlt = r
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if self.noAlt == r { self.noAlt = nil } }
        return false
    }
    /// The list redraws without the row; the highlight then lands on what is left.
    public func remove() {
        rows[row]?.remove?()
        DispatchQueue.main.async { self.move(0) }
    }
}

extension EnvironmentValues {
    /// Each panel sets its own; the default one serves pictures and previews, where nothing is ever open.
    @Entry public var popups = PopupState()
    /// A notification's second action (its alt link), by id; set once at the bar's root so the lists need no plumbing.
    @Entry public var onAltNote: (String) -> Void = { _ in }
}

/// A row the keyboard can land on: registers what Enter and x do, and shows the highlight.
struct NavRow: ViewModifier {
    let index: Int
    let choose: () -> Void
    let remove: (() -> Void)?
    var alt: (() -> Void)?
    @State private var me = UUID()
    @Environment(\.popups) private var popups
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let lit = popups.open != nil && popups.row == index
        content
            .background(lit ? theme[\.gold].opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .trailing) {
                if lit && popups.noAlt == index {
                    Text("No second action").font(.system(size: 11, weight: .medium)).foregroundStyle(theme[\.gold])
                        .padding(.horizontal, 6).background(theme[\.base], in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .onAppear(perform: register)
            .onChange(of: index) { old, _ in
                if popups.rows[old]?.owner == me { popups.rows[old] = nil }
                register()
            }
            // A row that moved to another index has already put itself there; only its own entry goes.
            .onDisappear { if popups.rows[index]?.owner == me { popups.rows[index] = nil } }
    }

    private func register() { popups.rows[index] = .init(owner: me, choose: choose, remove: remove, alt: alt) }
}

extension View {
    func navRow(_ index: Int, choose: @escaping () -> Void, remove: (() -> Void)? = nil, alt: (() -> Void)? = nil) -> some View {
        modifier(NavRow(index: index, choose: choose, remove: remove, alt: alt))
    }
}

/// `navRow` only when the row has a place.
struct OptionalNavRow: ViewModifier {
    let index: Int?
    let choose: () -> Void
    let remove: (() -> Void)?
    var alt: (() -> Void)?
    func body(content: Content) -> some View {
        if let index { content.navRow(index, choose: choose, remove: remove, alt: alt) } else { content }
    }
}
