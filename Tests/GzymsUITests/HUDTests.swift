import GzymsCore
import SwiftUI
import Testing
@testable import GzymsUI

@MainActor @Test func logFilterKeepsOnlyItsSource() {
    let logs = [LogLine(source: "anomalies", text: "a", level: nil), LogLine(source: "log", text: "b", level: nil)]
    #expect(LogFilter.anomalies.apply(logs).map(\.text) == ["a"])
    #expect(LogFilter.all.apply(logs).count == 2)
}

@MainActor @Test func hudQueuesTab() {
    var s = NotificationStore()
    func n(_ id: String, _ title: String, app: String?, level: NotifyLevel = .info, ago: Double) -> GzymsNotification {
        GzymsNotification(id: id, app: app, level: level, title: title, subtitle: nil, body: nil, link: nil, altLink: nil, sound: nil,
                          at: fixedNow - ago)
    }
    s.post(n("old", "Yesterday's build", app: "com.github", ago: 90_000), now: 0)
    s.tick(now: 12)
    s.post(n("e", "Deploy failed", app: "com.github", level: .error, ago: 300), now: 13)
    for (i, t) in ["Lunch?", "PR review", "Standup notes", "New comment", "Weekly digest"].enumerated() {
        s.post(n("i\(i)", t, app: "com.tinyspeck.slackmacgap", ago: Double(240 - i * 40)), now: 14)
    }
    let rows = s.saved(now: 15, wall: fixedNow).rows
    preview(HUDView(stats: HUDStats(lag: nil, cpu: nil, memMB: nil, panels: nil, rebuilds: nil, eventsPerSec: nil, answering: true,
                                    cpuSeries: [], lagSeries: []),
                    tab: .constant(.queues), logs: [], filter: .constant(.all), queues: rows, now: fixedNow)
        .frame(width: 300, height: 360).themed(.mochaNeon), "hud-queues")
}
