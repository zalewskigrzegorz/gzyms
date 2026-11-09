import Foundation
import Testing
@testable import GzymsCore

@Test func noReportBeforeThreshold() {
    var t = StallTracker(threshold: 0.25)
    #expect(t.tick(at: 0) == (true, nil) as (Bool, TimeInterval?))
    let r = t.tick(at: 0.1)
    #expect(r.sendPing == false && r.blocked == nil)
}

@Test func reportsAtThresholdThenFourTimes() {
    var t = StallTracker(threshold: 0.25)
    _ = t.tick(at: 0)
    #expect(t.tick(at: 0.25).blocked == 0.25)
    #expect(t.tick(at: 0.5).blocked == nil)
    #expect(t.tick(at: 1.0).blocked == 1.0)
    #expect(t.tick(at: 2.0).blocked == nil)
    #expect(t.tick(at: 4.0).blocked == 4.0)
}

@Test func pongResets() {
    var t = StallTracker(threshold: 0.25)
    _ = t.tick(at: 0)
    t.pong()
    #expect(t.tick(at: 5).sendPing == true)
    #expect(t.tick(at: 5.1).blocked == nil)
}

@Test func stallKinds() {
    // DarkWake 2026-11-02: 16 s with the screens off was a warning, now only a log line.
    #expect(StallTracker.kind(blocked: 16, asleep: true, settling: false) == "sleep_stall")
    #expect(StallTracker.kind(blocked: 16, asleep: true, settling: true) == "sleep_stall")
    #expect(StallTracker.kind(blocked: 4, asleep: false, settling: true) == "settling_stall")
    #expect(StallTracker.kind(blocked: 0.3, asleep: false, settling: false) == "main_thread_hitch")
    #expect(StallTracker.kind(blocked: 1, asleep: false, settling: false) == "main_thread_stall")
}

@Test func thirdRebuildInTenSecondsIsAStorm() {
    var s = RebuildStorm(limit: 3, window: 10)
    #expect(s.record(at: 0) == false)
    #expect(s.record(at: 1) == false)
    #expect(s.record(at: 2) == true)
}

@Test func rebuildsSpreadOutAreNotAStorm() {
    var s = RebuildStorm(limit: 3, window: 10)
    #expect([0, 11, 22].map { s.record(at: $0) } == [false, false, false])
}

@Test func logLineIsValidJSON() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let log = AnomalyLog(dir: dir)
    log.write(kind: "stall", detail: ["blocked_ms": "412"])
    let text = try String(contentsOf: dir.appendingPathComponent("anomalies.jsonl"), encoding: .utf8)
    let line = try #require(text.split(separator: "\n").first)
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    #expect(obj["kind"] as? String == "stall")
    #expect((obj["detail"] as? [String: String])?["blocked_ms"] == "412")
    #expect(obj["ts"] is String)
}

@Test func logRotatesAtFiveMegabytes() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("anomalies.jsonl")
    try Data(count: 5 * 1024 * 1024 + 1).write(to: file)
    AnomalyLog(dir: dir).write(kind: "stall", detail: [:])
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("anomalies.1.jsonl").path))
    #expect(try Data(contentsOf: file).count < 1024)
}

@Test func anomaliesCanBeTurnedOff() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let log = AnomalyLog(dir: dir)
    log.enabled = false
    log.write(kind: "x", detail: [:])
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("anomalies.jsonl").path))
    #expect(!loadConfig(toml: "[debug]\nanomalies = false").config.anomalies)
}

@Test func ncAndStallKindsAreWrittenWithTheDetectorOff() throws {
    // 2026-11-09: five NC restarts never reached the file because writing was off.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let log = AnomalyLog(dir: dir)
    log.enabled = false
    log.write(kind: "panel_rebuild", detail: [:])
    log.write(kind: "nc_restart", detail: [:])
    log.write(kind: "main_thread_stall", detail: [:])
    let text = try String(contentsOf: dir.appendingPathComponent("anomalies.jsonl"), encoding: .utf8)
    #expect(!text.contains("panel_rebuild"))
    #expect(text.contains("nc_restart") && text.contains("main_thread_stall"))
}

@Test func macContextDetail() {
    var c = MacContext()
    c.screenLocked = true
    c.focusOn = true
    c.screens = [MacContext.screen(builtin: true, width: 1512, height: 982, main: false),
                 MacContext.screen(builtin: false, width: 2560, height: 1440, main: true)]
    #expect(c.detail == ["screen_locked": "true", "display_asleep": "false", "focus": "on",
                         "screens": "builtin 1512x982, external 2560x1440 main"])
    c.countedApps = ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS"]
    c.sinceBanner = .some(nil)
    #expect(c.detail["counted_apps"] == "com.tinyspeck.slackmacgap,com.apple.MobileSMS")
    #expect(c.detail["since_banner_s"] == "none since start")
    c.sinceBanner = 312.7
    #expect(c.detail["since_banner_s"] == "312")
}
