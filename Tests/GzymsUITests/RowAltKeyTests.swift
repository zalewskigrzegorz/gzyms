import AppKit
import GzymsCore
import SwiftUI
import Testing
@testable import GzymsUI

/// `a` in an open popup: a row Gzyms linked runs its link, a plain row says it has no second action.
@MainActor @Test func aOnALinkedRowRunsItsAlt() {
    let popups = PopupState()
    var got: [RowAlt] = []
    var linked = PluginRow(id: "pr:1", text: "a")
    linked.agents = [RowAgent(key: "k", name: "n", state: .working)]
    linked.alt = .agent("k")
    let view = PluginMenuView(rows: [linked, PluginRow(id: "pr:2", text: "b")], onAlt: { got.append($0) }) { _, _ in }
    let host = NSHostingView(rootView: view.environment(\.popups, popups))
    host.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    popups.open = "p"
    popups.row = 0
    #expect(popups.alt())
    #expect(got == [.agent("k")])
    popups.row = 1
    #expect(!popups.alt())
    #expect(got.count == 1)
}
