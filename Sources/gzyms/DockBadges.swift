import AppKit
import ApplicationServices

/// The red labels on Dock icons (Slack's unread count, Mail's), read through Accessibility (`AXStatusLabel`).
/// Polled every 3 s on its own queue: the Dock posts no change notification for them.
final class DockBadges: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.gzyms.dock")
    private let deliver: @MainActor ([String: String]) -> Void
    private var last: [String: String] = [:]
    private var ids: [URL: String] = [:]  // app URL → bundle id, read once each
    private var timer: DispatchSourceTimer?
    private var reported = false

    init(deliver: @escaping @MainActor ([String: String]) -> Void) { self.deliver = deliver }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 3, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.read() }
        t.resume()
        timer = t
    }

    private func read() {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        var badges: [String: String] = [:]
        var items = 0
        defer {
            if !reported { log("dock: \(items) icons read, \(badges.count) with a badge"); reported = true }
        }
        for list in children(AXUIElementCreateApplication(dock.processIdentifier)) {
            for item in children(list) {
                items += 1
                guard let label = value(item, "AXStatusLabel") as? String, !label.isEmpty,
                      let url = (value(item, "AXURL") as? NSURL) as URL?, let id = bundleID(url) else { continue }
                badges[id] = label
            }
        }
        guard badges != last else { return }
        if Set(badges.keys) != Set(last.keys) { log("dock: badges on \(badges.keys.sorted().joined(separator: ", "))") }
        last = badges
        let found = badges  // a copy: the deferred log still reads `badges`
        DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver(found) } }
    }

    private func bundleID(_ url: URL) -> String? {
        if let hit = ids[url] { return hit }
        let id = Bundle(url: url)?.bundleIdentifier
        ids[url] = id
        return id
    }

    private func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    private func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
}
