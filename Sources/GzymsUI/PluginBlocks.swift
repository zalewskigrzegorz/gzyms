import Charts
import GzymsCore
import SwiftUI

/// The y range of a chart: its values and its reference line, padded so a flat series still sits in the middle. Bars start at zero.
func chartDomain(_ c: RowChart) -> ClosedRange<Double> {
    var lo = c.values.min() ?? 0, hi = c.values.max() ?? 1
    if let l = c.line?.value { lo = min(lo, l); hi = max(hi, l) }
    if c.kind == .bars { return min(0, lo)...(hi > 0 ? hi * 1.1 : 1) }
    let pad = hi > lo ? (hi - lo) * 0.08 : (hi == 0 ? 1 : abs(hi) * 0.005)
    return (lo - pad)...(hi + pad)
}

/// Plugins write numbers with a dot, so the chart does too, whatever the system locale.
private func number(_ v: Double, digits: ClosedRange<Int> = 0...4) -> String {
    v.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
}

/// Digits for the axis, from how wide the range is, so every tick has the same number of them.
/// `whole`: every value is a whole number (counts), so the ticks need no digits after the dot.
func axisDigits(_ d: ClosedRange<Double>, whole: Bool = false) -> Int {
    let span = d.upperBound - d.lowerBound
    if whole && span >= 2 { return 0 }
    return span < 0.1 ? 3 : span < 1 ? 2 : span < 10 ? 1 : 0
}

/// A big value on top of a popup, with its unit and its changes as chips.
struct HeadlineBlock: View {
    let row: PluginRow
    let headline: RowHeadline
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                pluginText(headline.value, theme).font(.system(size: 22, weight: .semibold).monospaced()).foregroundStyle(theme.tint(row.color))
                if let u = headline.unit { pluginText(u, theme).font(.system(size: 12)).foregroundStyle(theme[\.overlay]).lineLimit(1) }
            }
            if !headline.deltas.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(headline.deltas.enumerated()), id: \.offset) { _, d in
                        HStack(spacing: 4) {
                            pluginText(d.label, theme).foregroundStyle(theme[\.overlay])
                            pluginText(d.text, theme).fontWeight(.semibold).foregroundStyle(theme.tint(d.color))
                        }
                        .font(.system(size: 11).monospaced())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme[\.surface]))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A line (with a faded area and a dot on the last value) or bars, a dashed reference line, and a marker under the pointer.
struct ChartBlock: View {
    let chart: RowChart
    @State private var hovered: Int?
    @Environment(\.theme) private var theme

    var body: some View {
        let tint = theme.tint(chart.color ?? "sky")
        let domain = chartDomain(chart)
        let points = Array(chart.values.enumerated())
        let n = chart.values.count
        let digits = axisDigits(domain, whole: chart.values.allSatisfy { $0 == $0.rounded() } && (chart.line?.value ?? 0) == (chart.line?.value ?? 0).rounded())
        let ticks = chart.labels == nil ? [] : Array(Set([0, (n - 1) / 2, n - 1])).sorted()
        Chart {
            if chart.kind == .bars { bars(points, tint) } else { line(points, tint, domain) }
            if chart.kind == .line, let last = points.last {
                PointMark(x: .value("i", last.offset), y: .value("v", last.element)).foregroundStyle(tint).symbolSize(40)
            }
            if let r = chart.line {
                RuleMark(y: .value("rule", r.value))
                    .foregroundStyle(theme[\.peach]).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        if let l = r.label { Text("\(l) \(number(r.value, digits: digits...digits))").font(.system(size: 10).monospaced()).foregroundStyle(theme[\.peach]) }
                    }
            }
            if let h = hovered {
                RuleMark(x: .value("i", h)).foregroundStyle(theme[\.overlay]).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("i", h), y: .value("v", chart.values[h])).foregroundStyle(theme[\.text]).symbolSize(30)
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: chart.kind == .bars ? -0.5...(Double(n) - 0.5) : 0...Double(n - 1))
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisValueLabel(anchor: anchor(v.as(Int.self), n)) {
                    if let i = v.as(Int.self), let l = chart.labels?[i] { Text(l) }
                }
                .font(.system(size: 10).monospaced()).foregroundStyle(theme[\.overlay])
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(theme[\.overlay].opacity(0.25))
                AxisValueLabel { if let d = v.as(Double.self) { Text(number(d, digits: digits...digits)) } }.font(.system(size: 10).monospaced()).foregroundStyle(theme[\.overlay])
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let p) = phase, let frame = proxy.plotFrame,
                              let x = proxy.value(atX: p.x - geo[frame].origin.x, as: Double.self) else { hovered = nil; return }
                        hovered = min(n - 1, max(0, Int(x.rounded())))
                    }
            }
        }
        .frame(height: 140)
        .overlay(alignment: .topTrailing) {
            if let h = hovered {
                Text([chart.labels?[h], number(chart.values[h])].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11).monospaced()).foregroundStyle(theme[\.text])
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme[\.base]))
            }
        }
    }

    @ChartContentBuilder private func bars(_ points: [(offset: Int, element: Double)], _ tint: Color) -> some ChartContent {
        // an explicit start and end: on a number axis a ratio width has no unit to take a share of
        ForEach(points.filter { $0.element != 0 }.map { Bar(id: $0.offset, value: $0.element) }) { b in
            RectangleMark(xStart: .value("from", b.from), xEnd: .value("to", b.to), yStart: .value("zero", 0.0), yEnd: .value("v", b.value))
                .foregroundStyle(tint).cornerRadius(2)
        }
    }

    @ChartContentBuilder private func line(_ points: [(offset: Int, element: Double)], _ tint: Color, _ domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(points, id: \.offset) { p in
            AreaMark(x: .value("i", p.offset), yStart: .value("lo", domain.lowerBound), yEnd: .value("v", p.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("i", p.offset), y: .value("v", p.element))
                .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// The first label starts at its point and the last ends there, so neither leaves the chart.
    private func anchor(_ i: Int?, _ n: Int) -> UnitPoint { i == 0 ? .topLeading : i == n - 1 ? .topTrailing : .top }
}

/// One bar, 0.6 of its slot wide around its index.
private struct Bar: Identifiable {
    let id: Int
    let value: Double
    var from: Double { Double(id) - 0.3 }
    var to: Double { Double(id) + 0.3 }
}

/// Tiles of label and value, side by side in equal widths.
struct StatsBlock: View {
    let stats: [RowStat]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label.uppercased()).font(.system(size: 10)).tracking(0.6).foregroundStyle(theme[\.overlay]).lineLimit(1)
                    pluginText(s.value, theme).font(.system(size: 13, weight: .medium).monospaced()).foregroundStyle(theme.tint(s.color)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme[\.surface]))
            }
        }
    }
}

/// A level as lit segments in the row's colour.
struct MeterView: View {
    let meter: RowMeter
    let color: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<meter.max, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(i < meter.value ? theme.tint(color) : theme[\.overlay].opacity(0.3)).frame(width: 14, height: 8)
            }
        }
        .accessibilityElement().accessibilityLabel("\(meter.value) of \(meter.max)")
    }
}
