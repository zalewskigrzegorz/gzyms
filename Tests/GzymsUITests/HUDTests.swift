import Testing
@testable import GzymsUI

@MainActor @Test func logFilterKeepsOnlyItsSource() {
    let logs = [LogLine(source: "anomalies", text: "a", level: nil), LogLine(source: "log", text: "b", level: nil)]
    #expect(LogFilter.anomalies.apply(logs).map(\.text) == ["a"])
    #expect(LogFilter.all.apply(logs).count == 2)
}
