import SwiftUI

public struct Metric: Equatable, Sendable {
    public var now: Double
    public var max: Double
    public init(now: Double, max: Double) { self.now = now; self.max = max }
}

/// Everything the HUD shows. `nil` = unknown (no vitals yet), drawn as a dash.
public struct HUDStats: Equatable, Sendable {
    public var lag: Metric?
    public var cpu: Metric?
    public var memMB: Metric?
    public var panels: Int?
    public var rebuilds: Int?
    public var eventsPerSec: Double?
    public var answering: Bool
    public var cpuSeries: [Double]
    public var lagSeries: [Double]

    public init(lag: Metric?, cpu: Metric?, memMB: Metric?, panels: Int?, rebuilds: Int?, eventsPerSec: Double?,
                answering: Bool, cpuSeries: [Double], lagSeries: [Double]) {
        self.lag = lag; self.cpu = cpu; self.memMB = memMB; self.panels = panels; self.rebuilds = rebuilds
        self.eventsPerSec = eventsPerSec; self.answering = answering; self.cpuSeries = cpuSeries; self.lagSeries = lagSeries
    }
}

public enum HUDTab: Sendable { case stats, logs }

public struct LogLine: Equatable, Sendable {
    public var source: String
    public var text: String
    public var level: String?
    public init(source: String, text: String, level: String?) { self.source = source; self.text = text; self.level = level }
}

public enum LogFilter: String, CaseIterable, Sendable {
    case all, anomalies, log
    public func apply(_ lines: [LogLine]) -> [LogLine] { self == .all ? lines : lines.filter { $0.source == rawValue } }
}

enum HUDLimits {
    static let cpuHot = 3.0, lagHot = 100.0, memHot = 300.0
}

public struct HUDView: View {
    let stats: HUDStats
    @Binding var tab: HUDTab
    let logs: [LogLine]
    @Binding var filter: LogFilter
    let onHide: () -> Void
    @Environment(\.theme) private var theme

    public init(stats: HUDStats, tab: Binding<HUDTab>, logs: [LogLine], filter: Binding<LogFilter>,
                onHide: @escaping () -> Void = {}) {
        self.stats = stats; _tab = tab; self.logs = logs; _filter = filter; self.onHide = onHide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Usage HUD").font(.system(size: 12, weight: .semibold))
                Spacer()
                tabButton("Stats", .stats)
                tabButton("Logs", .logs)
                Text("hide 30 s").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    .padding(.leading, 4).onTapGesture(perform: onHide)
            }
            if !stats.answering {
                Text("bar not answering").font(.system(size: 11, weight: .bold)).foregroundStyle(theme[\.base])
                    .frame(maxWidth: .infinity).padding(3).background(theme[\.red], in: RoundedRectangle(cornerRadius: 4))
            }
            if tab == .stats { statsBody } else { logsBody }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11).monospaced())
        .foregroundStyle(theme[\.text])
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme[\.hud].opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
    }

    private func tabButton(_ title: String, _ t: HUDTab) -> some View {
        Text(title).font(.system(size: 11)).foregroundStyle(tab == t ? theme[\.text] : theme[\.overlay])
            .onTapGesture { tab = t }
    }

    @ViewBuilder private var statsBody: some View {
        row("main-thread lag", stats.lag, unit: " ms", hot: HUDLimits.lagHot, digits: 0)
        row("CPU", stats.cpu, unit: "%", hot: HUDLimits.cpuHot, digits: 1)
        row("memory", stats.memMB, unit: " MB", hot: HUDLimits.memHot, digits: 1)
        plain("panels", stats.panels.map(String.init))
        plain("rebuilds", stats.rebuilds.map(String.init))
        plain("events/s", stats.eventsPerSec.map { String(format: "%.1f", $0) })
        Text("CPU").foregroundStyle(theme[\.overlay]).padding(.top, 4)
        BarChart(values: stats.cpuSeries, threshold: HUDLimits.cpuHot, floor: 10, unit: "%")
        Text("main-thread lag").foregroundStyle(theme[\.overlay])
        BarChart(values: stats.lagSeries, threshold: HUDLimits.lagHot, floor: 250, unit: " ms")
    }

    private func row(_ label: String, _ m: Metric?, unit: String, hot: Double, digits: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let m {
                Text(String(format: "%.\(digits)f", m.now) + unit).foregroundStyle(m.now > hot ? theme[\.red] : theme[\.text])
                Text(String(format: "max %.\(digits)f", m.max)).foregroundStyle(m.max > hot ? theme[\.red] : theme[\.overlay])
                    .frame(width: 72, alignment: .trailing)
            } else {
                Text("–").foregroundStyle(theme[\.overlay])
            }
        }
    }

    private func plain(_ label: String, _ value: String?) -> some View {
        HStack { Text(label); Spacer(); Text(value ?? "–") }
    }

    @ViewBuilder private var logsBody: some View {
        HStack(spacing: 8) {
            Text("source").foregroundStyle(theme[\.overlay])
            Spacer()
            ForEach(LogFilter.allCases, id: \.self) { f in
                Text(f.rawValue).foregroundStyle(filter == f ? theme[\.text] : theme[\.overlay]).onTapGesture { filter = f }
            }
        }
        let shown = filter.apply(logs)
        if shown.isEmpty { Text("no events yet").foregroundStyle(theme[\.overlay]) }
        ForEach(Array(shown.prefix(16).enumerated()), id: \.offset) { _, line in
            Text(line.text).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(line.level == "error" ? theme[\.red] : theme[\.text])
                .font(.system(size: 10).monospaced())
        }
    }
}

/// A full-width line `at` a fraction of the height from the top.
struct ThresholdLine: Shape {
    let at: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.height * at))
        p.addLine(to: CGPoint(x: r.width, y: r.height * at))
        return p
    }
}

/// 60 s of bars: green below the threshold, red above, dashed threshold line, caption "<top><unit> · 60 s".
/// Same look as HyprMac's usage-monitor ChartView.
struct BarChart: View {
    let values: [Double]
    let threshold: Double
    let floor: Double
    let unit: String
    @Environment(\.theme) private var theme

    var body: some View {
        let top = max(floor, (values.max() ?? 0) * 1.1)
        let hot = threshold
        ZStack {
            BarsShape(values: values, top: top, only: { $0 <= hot }).fill(theme[\.green].opacity(0.8))
            BarsShape(values: values, top: top, only: { $0 > hot }).fill(theme[\.red])
            ThresholdLine(at: 1 - threshold / top).stroke(theme[\.overlay], style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .clipped()  // a threshold above the top stays out of sight, as it did in the Canvas
        .overlay(alignment: .topLeading) {
            Text("\(Int(top))\(unit) · 60 s").font(.system(size: 9)).foregroundStyle(theme[\.overlay])
        }
        .frame(height: 50)
    }
}
