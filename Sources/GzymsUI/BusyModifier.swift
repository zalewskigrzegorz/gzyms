import GzymsCore
import SwiftUI

extension View {
    /// Signs `name` into the busy registry while this view is in the tree and `on` holds (`gzyms debug cpu`).
    public func busy(_ name: String, while on: Bool = true) -> some View { modifier(BusyModifier(name: name, on: on)) }
}

private struct BusyModifier: ViewModifier {
    let name: String
    let on: Bool
    @State private var signed = false

    func body(content: Content) -> some View {
        content
            .onAppear { sync(on) }
            .onChange(of: on) { _, v in sync(v) }
            .onDisappear { sync(false) }
    }

    private func sync(_ want: Bool) {
        guard want != signed else { return }
        signed = want
        if want { GzymsCore.busy.start(name) } else { GzymsCore.busy.stop(name) }
    }
}
