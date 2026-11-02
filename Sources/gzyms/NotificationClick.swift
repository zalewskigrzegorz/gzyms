import AppKit
import ApplicationServices

/// Opens another app's notification the way its own banner would: presses the original in Notification Center,
/// so the app gets its own data (the thread, the chat, the event). Gzyms reads only the text; macOS hands that data
/// to the sending app alone. A trick, not an API: the panel opens with globe+N, moves off screen before it draws,
/// and the banner is found by its record's uuid. Needs the app's "Notification Center" box on and Accessibility.
/// shortcut: rides on the panel's Accessibility tree and the globe+N shortcut, a macOS update can break it;
/// then `done(false)` and the caller opens the app as before.
enum NotificationClick {
    private static let queue = DispatchQueue(label: "dev.gzyms.ncclick")

    static func press(uuid: String, done: @escaping @MainActor @Sendable (Bool) -> Void) {
        queue.async {
            let pressed = run(uuid)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(pressed) } }
        }
    }

    private static func run(_ uuid: String) -> Bool {
        guard AXIsProcessTrusted(),
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return false }
        let root = AXUIElementCreateApplication(nc.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        let start = Date()
        let wasOpen = window(root) != nil  // the user's own panel stays where it is
        if !wasOpen { toggle() }
        var panel: AXUIElement?
        while panel == nil, Date().timeIntervalSince(start) < 0.8 {
            panel = window(root)
            if panel == nil { Thread.sleep(forTimeInterval: 0.005) }
        }
        guard let panel else {
            log("nc click: Notification Center did not open (is the globe+N shortcut on?)")
            return false
        }
        if !wasOpen {
            var away = CGPoint(x: 20000, y: 20000)
            AXUIElementSetAttributeValue(panel, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &away)!)
        }
        // A grouped app shows a stack; a press opens it up, then its banners are there to find.
        var expanded = false
        while Date().timeIntervalSince(start) < 2 {
            if let hit = find(panel, { string($0, kAXIdentifierAttribute) == uuid }) {
                let isStack = string(hit, kAXSubroleAttribute) == "AXNotificationCenterBannerStack"
                let ok = AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success
                if !isStack { return ok }
            } else if !expanded {
                expanded = true
                all(panel).filter { string($0, kAXSubroleAttribute) == "AXNotificationCenterBannerStack" }
                    .forEach { AXUIElementPerformAction($0, kAXPressAction as CFString) }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        log("nc click: \(uuid) is not in Notification Center (its box off for that app?)")
        if !wasOpen { toggle() }
        return false
    }

    /// globe+N, the system shortcut that shows and hides the panel.
    private static func toggle() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: down)
            e?.flags = .maskSecondaryFn
            e?.post(tap: .cghidEventTap)
        }
    }

    private static func window(_ root: AXUIElement) -> AXUIElement? { (value(root, kAXWindowsAttribute) as? [AXUIElement])?.first }

    private static func find(_ e: AXUIElement, _ match: (AXUIElement) -> Bool, depth: Int = 0) -> AXUIElement? {
        if match(e) { return e }
        guard depth < 10 else { return nil }
        for c in children(e) { if let hit = find(c, match, depth: depth + 1) { return hit } }
        return nil
    }

    private static func all(_ e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        depth < 10 ? [e] + children(e).flatMap { all($0, depth: depth + 1) } : [e]
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func string(_ e: AXUIElement, _ name: String) -> String? { value(e, name) as? String }

    private static func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
}
