import Foundation
import Testing
@testable import GzymsCore

@Test func debugArgumentsTakeTopicsAndJson() {
    #expect(debugArguments([])?.topics == debugTopics)
    #expect(debugArguments(["keys"])?.topics == ["keys"])
    #expect(debugArguments(["--json", "notifications"])?.json == true)
    #expect(debugArguments(["keys", "nope"]) == nil)
}

@Test func debugRequestSurvivesTheWire() {
    let msg = debugRequest(id: "ab12-cd", topics: ["keys"])
    #expect(debugRequestParts(msg)?.id == "ab12-cd")
    #expect(debugRequestParts(msg)?.topics == ["keys"])
    #expect(debugRequestParts("ab12")?.topics == debugTopics)
    #expect(debugRequestParts("../x keys") == nil)  // the id names a file
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
