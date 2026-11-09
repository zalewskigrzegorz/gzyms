import Foundation
import Testing
@testable import GzymsCore

private let locked = Date(timeIntervalSince1970: 1_000)

private func note(_ id: String, app: String?, at: Double, compact: Bool = false) -> GzymsNotification {
    var n = GzymsNotification(id: id, app: app, level: .info, title: "t", subtitle: nil, body: nil,
                              link: nil, altLink: nil, sound: nil, at: Date(timeIntervalSince1970: at))
    n.compact = compact
    return n
}

@Test func nothingCameWhileLockedSaysNothing() {
    #expect(awayNotice(waiting: [note("a", app: "slack", at: 900)], since: locked, onBar: ["slack"]) == nil)
    #expect(awayNotice(waiting: [], since: locked, onBar: []) == nil)
}

@Test func countsOnlyWhatCameAfterTheLock() {
    let waiting = [note("old", app: "slack", at: 900), note("a", app: "slack", at: 1_100), note("b", app: "mail", at: 1_200),
                   note("pending", app: "slack", at: 1_300, compact: true), note(awayNoticeID, app: nil, at: 1_300)]
    let n = awayNotice(waiting: waiting, since: locked, onBar: ["slack"])
    #expect(n?.title == "2 notifications while you were away")
}

@Test func opensTheListWithMostOfThem() {
    let waiting = [note("a", app: "slack", at: 1_100), note("b", app: "cron", at: 1_100), note("c", app: nil, at: 1_100)]
    #expect(awayNotice(waiting: waiting, since: locked, onBar: ["slack"])?.list == "bell")
    let one = awayNotice(waiting: [note("a", app: "slack", at: 1_100)], since: locked, onBar: ["slack"])
    #expect(one?.title == "1 notification while you were away")
    #expect(one?.list == "app:slack")
}

@Test func aTieGoesToTheFirstListByName() {
    let waiting = [note("a", app: "slack", at: 1_100), note("b", app: "mail", at: 1_100)]
    #expect(awayNotice(waiting: waiting, since: locked, onBar: ["slack", "mail"])?.list == "app:mail")
}
