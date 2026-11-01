import AppKit
import GzymsCore

/// Turns screen-change and wake notifications into one debounced DisplayPlan.
@MainActor
final class ScreenManager {
    private let onPlan: (DisplayPlan, [UInt32: NSScreen]) -> Void
    private var current: Set<UInt32> = []
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(onPlan: @escaping (DisplayPlan, [UInt32: NSScreen]) -> Void) {
        self.onPlan = onPlan
    }

    func start() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.schedule("screens changed") } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.schedule("wake") } })
        evaluate("start")
    }

    private func schedule(_ reason: String) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.evaluate(reason) } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func evaluate(_ reason: String) {
        let byID = Dictionary(NSScreen.screens.compactMap { s in s.displayID.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
        let plan = planDisplays(current: current, next: Set(byID.keys))
        if !plan.changesNothing { log("display plan (\(reason))") }
        current = plan.keep.union(plan.create)
        onPlan(plan, byID)
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
