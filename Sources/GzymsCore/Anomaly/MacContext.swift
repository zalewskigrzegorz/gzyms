import Foundation

/// The state of the Mac when an NC alarm, an NC restart or a main-thread stall is written, so a report already holds
/// what a debug session on 2026-11-09 rebuilt by hand from pmset and Assertions.json over two hours.
public struct MacContext: Sendable, Equatable {
    public var screenLocked = false
    public var displayAsleep = false
    public var focusOn = false
    /// One label per online screen, from `screen(builtin:width:height:main:)`.
    public var screens: [String] = []
    /// Bundle ids whose deliveries the banner guard counted. Nil leaves the field out (stalls).
    public var countedApps: [String]?
    /// Seconds since the last banner Gzyms saw. `.some(nil)` is none since start, nil leaves the field out (stalls).
    public var sinceBanner: TimeInterval??

    public init() {}

    public static func screen(builtin: Bool, width: Int, height: Int, main: Bool) -> String {
        "\(builtin ? "builtin" : "external") \(width)x\(height)\(main ? " main" : "")"
    }

    /// Merged into the anomaly's own detail.
    public var detail: [String: String] {
        var d = ["screen_locked": String(screenLocked), "display_asleep": String(displayAsleep),
                 "focus": focusOn ? "on" : "off", "screens": screens.joined(separator: ", ")]
        if let countedApps { d["counted_apps"] = countedApps.joined(separator: ",") }
        if let sinceBanner { d["since_banner_s"] = sinceBanner.map { String(Int($0)) } ?? "none since start" }
        return d
    }
}
