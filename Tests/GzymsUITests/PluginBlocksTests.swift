import Testing
@testable import GzymsCore
@testable import GzymsUI

@Test func flatChartHasAPaddedDomain() {
    let d = chartDomain(RowChart(values: [4, 4, 4]))
    #expect(d.lowerBound < 4 && 4 < d.upperBound)
}

@Test func domainTakesTheRuleIn() {
    let d = chartDomain(RowChart(values: [3.9, 3.95], line: RowRule(value: 4.0)))
    #expect(d.upperBound >= 4.0 && d.lowerBound <= 3.9)
}

@Test func axisDigitsFollowTheSpan() {
    #expect(axisDigits(3.87...4.08) == 2)
    #expect(axisDigits(0...30) == 0)
    #expect(axisDigits(3.99...4.01) == 3)
    #expect(axisDigits(0...3.3, whole: true) == 0)  // counts per day: no "1.0"
}

/// The plugin sent fewer points while the pointer rested on the last one: no marker, no read past the end.
@Test func aHoverPastTheNewDataIsDropped() {
    #expect(hoverPoint(29, count: 29) == nil)
    #expect(hoverPoint(28, count: 29) == 28)
    #expect(hoverPoint(nil, count: 29) == nil)
}

@Test func barsStartAtZero() {
    #expect(chartDomain(RowChart(values: [1, 2], kind: .bars)).lowerBound == 0)
}
