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
}

@Test func barsStartAtZero() {
    #expect(chartDomain(RowChart(values: [1, 2], kind: .bars)).lowerBound == 0)
}
