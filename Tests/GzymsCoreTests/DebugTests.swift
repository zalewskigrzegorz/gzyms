import Foundation
import Testing
@testable import GzymsCore

@Test func debugArgumentsTakeTopicsAndJson() {
    #expect(debugArguments([])?.topics == ["notifications", "keys"])  // cpu takes 3 s: only when asked
    #expect(debugArguments(["keys"])?.topics == ["keys"])
    #expect(debugArguments(["cpu", "--json"])?.topics == ["cpu"])
    #expect(debugArguments(["--json", "notifications"])?.json == true)
    #expect(debugArguments(["keys", "nope"]) == nil)
}

@Test func debugRequestSurvivesTheWire() {
    let msg = debugRequest(id: "ab12-cd", topics: ["keys", "cpu"])
    #expect(debugRequestParts(msg)?.id == "ab12-cd")
    #expect(debugRequestParts(msg)?.topics == ["keys", "cpu"])
    #expect(debugRequestParts("ab12")?.topics == debugDefaultTopics)
    #expect(debugRequestParts("../x keys") == nil)  // the id names a file
}

@Test func busyRegistryCountsAndNeverGoesNegative() {
    var b = BusyRegistry()
    b.start("pulse"); b.start("pulse"); b.start("cat")
    #expect(b.names == ["cat", "pulse ×2"])
    b.stop("pulse"); b.stop("cat"); b.stop("cat")
    #expect(b.names == ["pulse"])
    b.stop("pulse")
    #expect(b.counts.isEmpty)
}

@Test func cpuReportGroupsWindowsAndHintsAtAFrameClock() {
    let idle = debugCPUReport(cpuSeconds: 0.03, wall: 3, wakeups: 12, rebuilds: 0, rebuildsTotal: 2, busy: [],
                              windows: [("BarPanel", "on screen"), ("BarPanel", "on screen"), ("SettingsPanel", "hidden"), ("BarPanel", "covered")])
    let v = Dictionary(idle.lines.map { ($0.key, $0.value) }) { a, _ in a }
    #expect(v["cpu.percent"] == "1.0")
    #expect(v["cpu.main_wakeups_per_s"] == "4")
    #expect(v["cpu.busy"] == "nothing")
    #expect(v["window.BarPanel"] == "on screen ×2, covered")
    #expect(v["window.SettingsPanel"] == "hidden")
    #expect(v["cpu.hint"] == nil)
    let leak = debugCPUReport(cpuSeconds: 0.15, wall: 3, wakeups: 180, rebuilds: 0, rebuildsTotal: 0, busy: ["settings: apps mirror pulse ×3"], windows: [])
    #expect(leak.lines.contains { $0.key == "cpu.hint" })
    #expect(leak.lines.contains { $0.value == "settings: apps mirror pulse ×3" })
}

@Test func debugReportKeepsOrderThroughTheWireAndPrintsOneFactPerLine() throws {
    var r = DebugReport()
    r.add("tap.enabled", true)
    r.add("secure_input", false)
    r.add("leader", "F13")
    let back = try #require(DebugReport(wire: r.wire()))
    #expect(back == r)
    #expect(back.text() == "tap.enabled: yes\nsecure_input: no\nleader: F13\n")
    let json = try #require(JSONSerialization.jsonObject(with: r.json()) as? [String: String])
    #expect(json["leader"] == "F13")
}

@Test func debugLineSaysWhatIsOff() {
    #expect(NCAppSettings().debugLine == "allow=on banners=temporary center=on sound=off previews=default")
    let bad = NCAppSettings(desktop: false, previews: 0, defaultHidden: true)
    #expect(bad.debugLine.contains("banners=off"))
    #expect(bad.debugLine.contains("previews=default (never)"))
    #expect(bad.debugLine.hasSuffix("problems: Banners off, Previews off"))
    #expect(NCAppSettings(unsupported: true).debugLine.hasPrefix("unsupported"))
}

@Test func debugAgoIsShort() {
    let now = Date()
    #expect(debugAgo(nil, now: now) == "never")
    #expect(debugAgo(now.addingTimeInterval(-12), now: now) == "12 s ago")
    #expect(debugAgo(now.addingTimeInterval(-600), now: now) == "10 min ago")
    #expect(debugAgo(now.addingTimeInterval(-7200), now: now) == "2 h ago")
}

@Test func bannerGuardShowsItsCounters() {
    var g = BannerGuard()
    g.signal(at: 5)
    g.signal(at: 9)
    #expect(g.signals == 2)
    #expect(g.firstSignal == 5)
    g.banner(at: 10)
    #expect(g.signals == 0 && g.firstSignal == nil)
}
