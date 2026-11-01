import AppKit
import GzymsCore
import SwiftUI

/// The black island that drops from the top edge (from the notch, where there is one) with one notification.
public struct BannerView: View {
    let n: GzymsNotification
    let icon: NSImage?
    let remaining: Double?
    let total: Double?
    /// false while the pointer holds the banner: the bar stands still.
    let running: Bool
    /// Shown while Ctrl is held.
    let hints: ChordHints?
    /// Height of the notch above the content; 0 on a screen without one.
    let topInset: CGFloat
    /// Banners waiting under this one, the next first: one edge each in its level's colour, at most three (M3c).
    let queue: [GzymsNotification]
    var waiting: Int { queue.count }
    @Environment(\.theme) private var theme

    public static let width: CGFloat = 340
    static let barWidth: CGFloat = width
    static let radius: CGFloat = 20

    public init(n: GzymsNotification, icon: NSImage?, remaining: Double?, total: Double?, running: Bool = false, hints: ChordHints? = nil, topInset: CGFloat = 0, queue: [GzymsNotification] = []) {
        self.n = n; self.icon = icon; self.remaining = remaining; self.total = total; self.running = running; self.hints = hints; self.topInset = topInset
        self.queue = queue
    }

    public static let edgeHeight: CGFloat = 5, edgeGap: CGFloat = 2
    public static func edges(_ waiting: Int) -> Int { min(waiting, NotificationStore.maxWaiting) }

    public static let compactWidth: CGFloat = 64

    public var body: some View {
        if n.compact { compactBody } else {
            VStack(spacing: Self.edgeGap) {
                fullBody
                // A stack seen from the front: each card behind a little narrower, a gap between them so each one counts.
                // Solid in the waiting one's level colour, so it reads on a light screen too and says what waits (Greg).
                ForEach(Array(queue.prefix(Self.edges(waiting)).enumerated()), id: \.offset) { i, w in
                    UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                        .fill(levelColor(w))
                        .frame(width: Self.width - CGFloat(i + 1) * 28, height: Self.edgeHeight)
                }
            }
        }
    }

    /// Only the app's icon, pulsing, while the text is on its way (prototype).
    private var compactBody: some View {
        Group {
            if let icon { PulsingIcon(image: icon) } else { avatar }
        }
        .frame(width: 36, height: 36)
        .padding(.horizontal, 14)
        .padding(.top, topInset + 12)
        .padding(.bottom, 14)
        .frame(width: Self.compactWidth)
        .background(topInset > 0 ? theme[\.island] : theme[\.base])
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.radius, bottomTrailingRadius: Self.radius))
        // Too narrow for the hint text: a gold outline says Ctrl is held (⌃O open, ⌃X dismiss work here too).
        .overlay { if hints != nil { OpenTopOutline(radius: Self.radius).stroke(theme[\.gold], lineWidth: 2) } }
        .pointerStyle(.link)
    }

    private var fullBody: some View {
        HStack(alignment: .center, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                if n.meetingStart != nil {
                    Label("meeting", systemImage: "video.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                } else if n.reminder {
                    Label("reminder", systemImage: "clock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[\.gold])
                }
                Text(n.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let s = n.subtitle {
                    let loud = late || startingNow
                    Text(s).font(.system(size: startingNow ? 14 : 12, weight: loud ? .bold : .regular))
                        .foregroundStyle(loud ? accent : theme[\.overlay]).lineLimit(1)
                }
                if let b = n.body { Text(b).font(.system(size: 12)).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                if let hints {
                    Text(hints.text(alt: n.altLink != nil, waiting: waiting)).font(.system(size: 11, weight: .medium).monospaced())
                        .foregroundStyle(theme[\.gold]).padding(.top, 4)
                }
            }
            // The island under a notch is black in every theme: a light theme's dark text would vanish there.
            .foregroundStyle(topInset > 0 && !theme.isDark ? theme[\.base] : theme[\.text])
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, topInset + 12)
        .padding(.bottom, 14)
        .frame(width: Self.width, alignment: .leading)
        // Black only where it grows out of the black notch; elsewhere it is part of the bar (Greg).
        .background(topInset > 0 ? theme[\.island] : theme[\.base])
        // As in the prototype: the countdown runs along the bottom, inside the outline.
        .overlay(alignment: .bottom) { countdown.padding(.bottom, outlined ? 2 : 0) }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.radius, bottomTrailingRadius: Self.radius))
        // Anything above info, and reminders, get a U of their colour: sides and bottom, the top hides under the bar or notch.
        .overlay { if outlined { OpenTopOutline(radius: Self.radius).stroke(accent, lineWidth: 2) } }
        .pointerStyle(.link)
    }

    /// Shrinks to nothing as the time runs out; a full line when the banner stays until acted on.
    @ViewBuilder private var countdown: some View {
        let now = Date().timeIntervalSince1970
        if let start = n.meetingStart, let end = n.meetingEnd, now >= start, end > now {
            // Once it has started: red fills in how much of the meeting is gone, over a faint track of the whole of it.
            CountdownBar(fraction: (now - start) / (end - start), seconds: end - now, color: NSColor(theme[\.red]), fill: true)
                .frame(width: Self.barWidth, height: 3)
                .background(theme[\.red].opacity(0.25))
        } else {
            let fraction = total.flatMap { t in remaining.map { min(1, max(0, $0 / t)) } } ?? 1
            CountdownBar(fraction: fraction, seconds: running ? remaining : nil, color: NSColor(theme[\.mauve]))
                .frame(width: Self.barWidth, height: 3)
        }
    }

    private var outlined: Bool { n.level != .info || n.reminder || n.meetingStart != nil }

    /// The first minute after the start, while the subtitle says "starting now": peach, bigger.
    private var startingNow: Bool { n.meetingStart.map { (0..<60).contains(Date().timeIntervalSince1970 - $0) } ?? false }

    /// From "1 min late" on: the subtitle and the outline turn red.
    private var late: Bool { n.meetingStart.map { Date().timeIntervalSince1970 >= $0 + 60 } ?? false }

    /// The app's icon, or a circle in the level colour with the title's first letter (prototype).
    @ViewBuilder private var avatar: some View {
        if let icon {
            Image(nsImage: icon).resizable().frame(width: 36, height: 36)
        } else {
            Text(n.title.prefix(1).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme[\.base])
                .frame(width: 36, height: 36)
                .background(Circle().fill(accent))
        }
    }

    private var accent: Color {
        if n.meetingStart != nil { return late ? theme[\.red] : startingNow ? theme[\.peach] : theme[\.sky] }
        return levelColor(n)
    }

    private func levelColor(_ n: GzymsNotification) -> Color {
        if n.meetingStart != nil { return theme[\.sky] }
        if n.reminder { return theme[\.gold] }
        return switch n.level {
        case .info: theme[\.sky]
        case .warning: theme[\.peach]
        case .error, .critical: theme[\.red]
        case .armageddon: theme[\.mauve]
        }
    }
}

/// A Core Animation pulse, like the countdown: the window server draws it, Gzyms spends nothing.
private struct PulsingIcon: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> PulseView { PulseView() }

    func updateNSView(_ v: PulseView, context: Context) {
        v.icon.contents = image.layerContents(forContentsScale: v.window?.backingScaleFactor ?? 2)
        guard v.icon.animation(forKey: "pulse") == nil else { return }
        let a = CABasicAnimation(keyPath: "transform.scale")
        a.fromValue = 1
        a.toValue = 0.88
        a.duration = 0.7
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        v.icon.add(a, forKey: "pulse")
    }
}

final class PulseView: NSView {
    let icon = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        icon.contentsGravity = .resizeAspect
        layer?.addSublayer(icon)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        icon.frame = bounds  // a sublayer scales around its centre
    }
}

/// Sides and rounded bottom; no top edge (prototype).
private struct OpenTopOutline: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius - 1)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius - 1)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// The banner's letters, shown while the keyboard mode is on (plain letters) or a modifier leader is held (⌃O).
public struct ChordHints: Equatable, Sendable {
    /// Set once z was pressed: the snooze settles after a short pause or when the leader goes up.
    public var snoozeMinutes: Int?
    public var verbs: Verbs
    /// The held modifier leader's symbol ("⌃"); nil = the mode is on, the letters go alone.
    public var hold: String?
    /// Says something for a moment in place of the letters ("No second action").
    public var note: String?
    public init(snoozeMinutes: Int?, verbs: Verbs = Verbs(), hold: String? = nil, note: String? = nil) {
        self.snoozeMinutes = snoozeMinutes; self.verbs = verbs; self.hold = hold; self.note = note
    }

    func text(alt: Bool, waiting: Int = 0) -> String {
        if let note { return note }
        let v = verbs, h = hold ?? ""
        let k = { (l: String) in h.isEmpty ? l : h + l.uppercased() }
        if let m = snoozeMinutes { return "snooze \(m) min · \(k(v.snooze)) for longer" }
        return "\(k(v.open)) open · \(k(v.dismiss)) dismiss · \(k(v.snooze)) snooze" + (alt ? " · \(k(v.alt)) alt" : "")
            + (waiting > 0 ? "\n\(k(v.next))/\(k(v.prev)) \(waiting) more" : "")
    }
}

/// The countdown runs as a Core Animation animation, so the window server draws it and Gzyms spends nothing.
/// A SwiftUI timeline redrew it in-process and cost ~4% CPU for as long as a banner was up.
private struct CountdownBar: NSViewRepresentable {
    let fraction: Double
    let seconds: Double?
    let color: NSColor
    /// true = grows to full in `seconds` (meeting progress) instead of shrinking to nothing.
    var fill = false

    func makeNSView(context: Context) -> BarLayerView { BarLayerView() }

    func updateNSView(_ v: BarLayerView, context: Context) {
        v.fraction = fraction; v.color = color
        v.needsDisplay = true
        v.bar.removeAllAnimations()
        v.bar.isHidden = seconds == nil
        guard let seconds, seconds > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        v.bar.backgroundColor = color.cgColor
        v.bar.frame = CGRect(x: 0, y: 0, width: BannerView.barWidth * fraction, height: 3)
        v.bar.bounds.size.width = fill ? BannerView.barWidth : 0
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "bounds.size.width")
        a.fromValue = BannerView.barWidth * fraction
        a.toValue = fill ? BannerView.barWidth : 0
        a.duration = seconds
        v.bar.add(a, forKey: "countdown")
    }
}

final class BarLayerView: NSView {
    let bar = CALayer()
    var fraction = 1.0
    var color: NSColor?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        bar.anchorPoint = .zero
        layer?.addSublayer(bar)
    }

    required init?(coder: NSCoder) { nil }

    /// The still bar (paused, until acted on, previews); the moving one is the sublayer.
    override func draw(_ dirtyRect: NSRect) {
        guard bar.isHidden, let color else { return }
        color.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height).fill()
    }
}
