// Portions adapted from NotificationNanny (https://github.com/chessper53/NotificationNanny), MIT License, Copyright (c) 2026 chessper53
// (AXSupport.swift, AppNameResolver.swift, NCActionNames.swift, NCPanelTakeover.swift: isPanelOpen, hostWindow, pressMenuBarClock).
import AppKit
import ApplicationServices
import GzymsCore

/// Notification Center's banners and panel through Accessibility. Since macOS 26 banners and the panel share one
/// fullscreen `AXSystemDialog` host window; a banner's `AXIdentifier` is its record's uuid, the same in the panel.
enum NCAX {
    static let bundleID = "com.apple.notificationcenterui"
    static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner", "AXNotificationCenterBannerStack",
        "AXNotificationCenterAlert", "AXNotificationCenterAlertStack",
    ]
    /// Off screen: x stays, y goes far above every display.
    static let parkedY: CGFloat = -9999

    static func isParked(_ p: CGPoint) -> Bool { p.y < parkedY / 2 }

    /// Every banner under `el`, newest first. Below depth 7 there are only the banners' own parts.
    static func banners(in el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 7 else { return [] }
        if let sr = el.subrole, bannerSubroles.contains(sr) { return [el] }
        return el.children.flatMap { banners(in: $0, depth: depth + 1) }
    }

    static func find(in el: AXUIElement, id: String, depth: Int = 0) -> AXUIElement? {
        guard depth < 12 else { return nil }
        if el.identifier == id { return el }
        for c in el.children { if let hit = find(in: c, id: id, depth: depth + 1) { return hit } }
        return nil
    }

    static func all(in el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        depth < 12 ? [el] + el.children.flatMap { all(in: $0, depth: depth + 1) } : [el]
    }

    /// App name from the description's prefix ("Slack, Anna, …"), the rest from the labelled static texts.
    static func read(_ el: AXUIElement) -> BannerLines {
        let desc = el.str("AXAttributedDescription") ?? ""
        let lines = el.labelledText()
        return BannerLines(app: cleanAXString(desc.components(separatedBy: ", ").first ?? ""),
                           title: lines["title"] ?? "", subtitle: lines["subtitle"] ?? "", body: lines["body"] ?? "")
    }

    /// The menu bar clock opens and closes the panel, found by hit testing. Not there when the menu bar is hidden.
    static func pressMenuBarClock() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let system = AXUIElementCreateSystemWide()
        let right = Int(screen.frame.maxX)
        for x in stride(from: right - 1, through: right - 500, by: -6) {
            var el: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(x), 12, &el) == .success, let el,
                  el.identifier == "com.apple.menuextra.clock" else { continue }
            return el.press() == .success
        }
        return false
    }

    /// globe+N, the system shortcut that shows and hides the panel.
    static func pressGlobeN() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: down)
            e?.flags = .maskSecondaryFn
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Opens or closes the panel; "clock" or "globeN", so the close goes the way the open went.
    static func toggle(prefer: String? = nil) -> String {
        if prefer != "globeN", pressMenuBarClock() { return "clock" }
        pressGlobeN()
        return "globeN"
    }

    /// Close and Clear All in every language Notification Center ships: it names its actions in the system's.
    static let closeNames: Set<String> = {
        var names: Set<String> = ["Close", "Clear All"]
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/NotificationCenter.app")
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Resources/Localizable.loctable")),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return names }
        for case let strings as [String: Any] in table.values {
            for key in ["Close", "Clear All"] { if let n = strings[key] as? String, !n.isEmpty { names.insert(n) } }
        }
        return names
    }()
}

/// Notification Center's process, as Accessibility sees it.
struct NCApp {
    let pid: pid_t
    let app: AXUIElement

    static func find() -> NCApp? {
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: NCAX.bundleID).first else { return nil }
        return NCApp(pid: nc.processIdentifier, app: AXUIElementCreateApplication(nc.processIdentifier))
    }

    var windows: [AXUIElement] { app.attr(kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    /// The panel is open: Notification Center's own word. The first window is no proof, banners and widgets are windows too.
    var panelOpen: Bool { (app.attr("AXExpanded") as? Bool) ?? false }
    /// The fullscreen host of banners and the panel: the widest `AXSystemDialog`, never a desktop widget.
    var host: AXUIElement? {
        windows.filter { $0.subrole == "AXSystemDialog" }.max { ($0.size?.width ?? 0) < ($1.size?.width ?? 0) }
    }
}

extension AXUIElement {
    func attr(_ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &v) == .success ? v : nil
    }

    func str(_ name: String) -> String? {
        guard let v = attr(name) else { return nil }
        if let s = v as? String { return s }
        if CFGetTypeID(v) == CFAttributedStringGetTypeID() { return CFAttributedStringGetString((v as! CFAttributedString)) as String }
        return nil
    }

    var role: String? { str(kAXRoleAttribute) }
    var subrole: String? { str(kAXSubroleAttribute) }
    var identifier: String? { str(kAXIdentifierAttribute) }
    var children: [AXUIElement] { attr(kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    var point: CGPoint? {
        guard let v = attr(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }

    var size: CGSize? {
        guard let v = attr(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &s)
        return s
    }

    @discardableResult
    func setPoint(_ p: CGPoint) -> AXError {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
        return AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, v)
    }

    @discardableResult
    func press() -> AXError { AXUIElementPerformAction(self, kAXPressAction as CFString) }

    /// title / subtitle / body, the labelled AXStaticText children a banner has since macOS 26.
    func labelledText() -> [String: String] {
        var out: [String: String] = [:]
        for c in children where c.role == kAXStaticTextRole {
            guard let id = c.identifier, let v = c.str(kAXValueAttribute) else { continue }
            let s = cleanAXString(v)
            if !s.isEmpty { out[id] = s }
        }
        return out
    }

    /// Performs the first action whose name ("Name:Close\n…" for custom ones) is in `names`.
    func perform(anyOf names: Set<String>) -> Bool {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(self, &ref) == .success, let actions = ref as? [String] else { return false }
        func name(_ a: String) -> String { a.hasPrefix("Name:") ? String(a.dropFirst(5).prefix { $0 != "\n" }) : a }
        guard let action = actions.first(where: { names.contains(name($0)) }) else { return false }
        return AXUIElementPerformAction(self, action as CFString) == .success
    }
}
