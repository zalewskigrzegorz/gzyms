import GzymsCore
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

public enum HUDTab: Sendable { case stats, logs, queues }

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
    /// Seconds in a row above `cpuHot` before the CPU chart turns red.
    static let cpuRun = 3
}

public struct HUDView: View {
    let stats: HUDStats
    @Binding var tab: HUDTab
    let logs: [LogLine]
    @Binding var filter: LogFilter
    /// The same rows as `gzyms notifications`.
    let queues: [NotificationRow]
    let now: Date
    let onHide: () -> Void
    @Environment(\.theme) private var theme

    public init(stats: HUDStats, tab: Binding<HUDTab>, logs: [LogLine], filter: Binding<LogFilter>,
                queues: [NotificationRow] = [], now: Date = Date(), onHide: @escaping () -> Void = {}) {
        self.stats = stats; _tab = tab; self.logs = logs; _filter = filter; self.queues = queues; self.now = now; self.onHide = onHide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Usage HUD").font(.system(size: 12, weight: .semibold))
                Spacer()
                tabButton("Stats", .stats)
                tabButton("Logs", .logs)
                tabButton("Queues", .queues)
                Text("hide 30 s").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                    .padding(.leading, 4).onTapGesture(perform: onHide)
            }
            if !stats.answering {
                Text("bar not answering").font(.system(size: 11, weight: .bold)).foregroundStyle(theme[\.base])
                    .frame(maxWidth: .infinity).padding(3).background(theme[\.red], in: RoundedRectangle(cornerRadius: 4))
            }
            switch tab {
            case .stats: statsBody
            case .logs: logsBody
            case .queues: queuesBody
            }
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
        let cpuHot = sustainedHot(stats.cpuSeries, above: HUDLimits.cpuHot, run: HUDLimits.cpuRun)
        row("CPU", stats.cpu, unit: "%", hot: HUDLimits.cpuHot, digits: 1, nowHot: cpuHot.last ?? false, maxHot: cpuHot.contains(true))
        row("memory", stats.memMB, unit: " MB", hot: HUDLimits.memHot, digits: 1)
        plain("panels", stats.panels.map(String.init))
        plain("rebuilds", stats.rebuilds.map(String.init))
        plain("events/s", stats.eventsPerSec.map { String(format: "%.1f", $0) })
        Text("CPU").foregroundStyle(theme[\.overlay]).padding(.top, 4)
        BarChart(values: stats.cpuSeries, threshold: HUDLimits.cpuHot, floor: 10, unit: "%", run: HUDLimits.cpuRun)
        Text("main-thread lag").foregroundStyle(theme[\.overlay])
        BarChart(values: stats.lagSeries, threshold: HUDLimits.lagHot, floor: 250, unit: " ms")
    }

    /// `nowHot` / `maxHot` override the plain "above `hot`" test (the CPU row reds only a sustained spell).
    private func row(_ label: String, _ m: Metric?, unit: String, hot: Double, digits: Int, nowHot: Bool? = nil, maxHot: Bool? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let m {
                Text(String(format: "%.\(digits)f", m.now) + unit).foregroundStyle(nowHot ?? (m.now > hot) ? theme[\.red] : theme[\.text])
                Text(String(format: "max %.\(digits)f", m.max)).foregroundStyle(maxHot ?? (m.max > hot) ? theme[\.red] : theme[\.overlay])
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

    /// Columns: position, level, how long ago it came, ♪ = its sound played, title, source.
    @ViewBuilder private var queuesBody: some View {
        let stack = queues.filter { $0.place == .stack }, waiting = queues.filter { $0.place == .waiting }
        Text("stack · \(stack.count) of 4, 1 on screen").foregroundStyle(theme[\.overlay])
        if stack.isEmpty { Text("empty").foregroundStyle(theme[\.overlay]) }
        ForEach(stack) { queueRow($0) }
        Text("waiting for room · \(waiting.count)").foregroundStyle(theme[\.overlay]).padding(.top, 4)
        ForEach(waiting.prefix(8)) { queueRow($0) }
        if waiting.count > 8 { Text("+\(waiting.count - 8) more").foregroundStyle(theme[\.overlay]) }
        plain("in the lists", "\(queues.filter { $0.place == .list }.count)").padding(.top, 4)
        plain("missed", "\(queues.filter { $0.place == .missed }.count)")
        plain("snoozed", "\(queues.filter { $0.place == .snoozed }.count)")
    }

    private func queueRow(_ r: NotificationRow) -> some View {
        let color = switch r.level {
        case .armageddon, .critical, .error: theme[\.red]
        case .warning: theme[\.peach]
        case .info: theme[\.overlay]
        }
        return HStack(spacing: 5) {
            Text(r.position.map(String.init) ?? "").frame(width: 12, alignment: .trailing)
            Text(["error": "err", "critical": "crit", "armageddon": "arma"][r.level.rawValue] ?? r.level.rawValue.prefix(4)).foregroundStyle(color).frame(width: 30, alignment: .leading)
            Text(Self.ago(now.timeIntervalSince(r.at))).frame(width: 28, alignment: .trailing)
            Text(r.heard == true ? "♪" : " ").frame(width: 10)
            Text(r.title.isEmpty ? "–" : r.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(r.source.split(separator: ".").last.map(String.init) ?? r.source).foregroundStyle(theme[\.overlay]).lineLimit(1)
        }
        .font(.system(size: 10).monospaced())
    }

    static func ago(_ s: Double) -> String {
        let s = max(0, s)
        return switch s {
        case ..<60: "\(Int(s))s"
        case ..<3600: "\(Int(s / 60))m"
        case ..<86_400: "\(Int(s / 3600))h"
        default: "\(Int(s / 86_400))d"
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
    /// Samples in a row above `threshold` before a bar turns red; 1 = every bar above it.
    var run = 1
    @Environment(\.theme) private var theme

    var body: some View {
        let top = max(floor, (values.max() ?? 0) * 1.1)
        let red = sustainedHot(values, above: threshold, run: run)
        let hotValues = zip(values, red).map { $1 ? $0 : 0 }, calmValues = zip(values, red).map { $1 ? 0 : $0 }
        ZStack {
            BarsShape(values: calmValues, top: top, only: { $0 > 0 }).fill(theme[\.green].opacity(0.8))
            BarsShape(values: hotValues, top: top, only: { $0 > 0 }).fill(theme[\.red])
            ThresholdLine(at: 1 - threshold / top).stroke(theme[\.overlay], style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .clipped()  // a threshold above the top stays out of sight, as it did in the Canvas
        .overlay(alignment: .topLeading) {
            Text("\(Int(top))\(unit) · 60 s").font(.system(size: 9)).foregroundStyle(theme[\.overlay])
        }
        .frame(height: 50)
    }
}
