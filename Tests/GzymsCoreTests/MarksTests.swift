import Foundation
import Testing
@testable import GzymsCore

@Test func markKeepsTheLinesAroundIt() {
    let opened = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15T08:00:00Z
    let log = """
        2027-01-15T07:54:59Z too old
        2027-01-15T07:55:00Z banners: first in
        a line without a time
        2027-01-15T08:00:30Z island: typed while open
        2027-01-15T08:02:00Z after save
        """
    let anomalies = #"{"detail":{},"kind":"nc_stuck","ts":"2027-01-15T07:59:00Z"}"#
    let t = Marks.text(note: "baner bez dźwięku", openedAt: opened, now: opened + 60, logs: [("gzyms.log", log), ("anomalies.jsonl", anomalies)])
    #expect(t == """
        note: baner bez dźwięku
        opened: 2027-01-15T08:00:00Z
        saved: 2027-01-15T08:01:00Z

        == gzyms.log (2 lines)
        2027-01-15T07:55:00Z banners: first in
        2027-01-15T08:00:30Z island: typed while open

        == anomalies.jsonl (1 lines)
        {"detail":{},"kind":"nc_stuck","ts":"2027-01-15T07:59:00Z"}

        """)
    #expect(Marks.fileName(opened) == "2027-01-15T08-00-00Z.txt")
    #expect(loadConfig(toml: "[debug]\nmarks = true").config.marks)
    #expect(!GzymsConfig.defaults.marks)
}
