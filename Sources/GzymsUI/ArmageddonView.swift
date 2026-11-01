import AppKit
import GzymsCore
import SwiftUI

/// An armageddon: the whole screen flashes red until it is clicked. One per screen.
public struct ArmageddonView: View {
    let n: GzymsNotification
    let icon: NSImage?
    /// Reduce motion or animations off: a slow pulse instead of the flashing.
    let calm: Bool
    /// Previews and tests pin the frame; nil = it runs.
    let at: Date?
    @Environment(\.theme) private var theme

    public init(n: GzymsNotification, icon: NSImage?, calm: Bool, at: Date? = nil) {
        self.n = n; self.icon = icon; self.calm = calm; self.at = at
    }

    /// How red the screen is at `t` (0 dark … 1 full red). Flashing: 2 a second, under the 3 a second
    /// photosensitivity limit (WCAG 2.3.1). Calm: a 2 s sine between half and full.
    public static func red(at t: TimeInterval, calm: Bool) -> Double {
        calm ? 0.75 + 0.25 * sin(t * .pi) : (Int((t * 4).rounded(.down)) % 2 == 0 ? 1 : 0)
    }

    public var body: some View {
        if let at { frame(at) } else {
            TimelineView(.periodic(from: .now, by: calm ? 0.1 : 0.25)) { ctx in frame(ctx.date) }
        }
    }

    private func frame(_ date: Date) -> some View {
        let r = Self.red(at: date.timeIntervalSinceReferenceDate, calm: calm)
        return ZStack {
            theme[\.base]
            theme[\.red].opacity(0.25 + 0.6 * r)
            VStack(spacing: 18) {
                Label("ARMAGEDDON", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .heavy)).tracking(4)
                if let icon { Image(nsImage: icon).resizable().frame(width: 96, height: 96) }
                Text(n.title).font(.system(size: 44, weight: .bold)).multilineTextAlignment(.center).lineLimit(3)
                if let s = n.subtitle { Text(s).font(.system(size: 24, weight: .semibold)).multilineTextAlignment(.center) }
                if let b = n.body { Text(b).font(.system(size: 18)).multilineTextAlignment(.center).lineLimit(6) }
                Text("Click to open it. Right click to dismiss.")
                    .font(.system(size: 14, weight: .medium)).opacity(0.8).padding(.top, 24)
            }
            .foregroundStyle(theme[\.text])
            .padding(48)
            .frame(maxWidth: 900)
            .background(RoundedRectangle(cornerRadius: 28).fill(theme[\.base].opacity(0.85)))
        }
        .ignoresSafeArea()
        .pointerStyle(.link)
    }
}
