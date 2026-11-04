import GzymsCore
import SwiftUI

/// Settings → Apps, step by step (Greg, 2026-11-04: variant D). Floats next to System Settings, which shows this app's
/// page. What to click there pulses here; Gzyms reads the change itself and opens the next app.
public struct AppSetupView: View {
    let app: SeenApp
    let step: Int, total: Int
    let skip: () -> Void, stop: () -> Void
    @Environment(\.theme) private var theme

    public init(app: SeenApp, step: Int, total: Int, skip: @escaping () -> Void, stop: @escaping () -> Void) {
        self.app = app; self.step = step; self.total = total; self.skip = skip; self.stop = stop
    }

    private var done: Bool { app.mac?.pageDone ?? false }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App \(step) of \(total)").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                Spacer()
                Button("Stop", action: stop)
            }
            HStack(spacing: 8) {
                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                Text(app.name).font(.system(size: 15, weight: .semibold))
            }
            Text(done ? "Set up right. The next app opens in a moment." : "Click what pulses below on its page in System Settings. Gzyms moves on by itself.")
                .font(.system(size: 12)).foregroundStyle(done ? theme[\.green] : theme[\.text])
                .fixedSize(horizontal: false, vertical: true)
            MacMirror(settings: app.mac).id(app.id)
            HStack {
                if !done {
                    Circle().fill(theme[\.peach]).frame(width: 7, height: 7)
                    Text("Waiting for the change in macOS").font(.system(size: 11)).foregroundStyle(theme[\.overlay])
                }
                Spacer()
                Button(step == total ? "Skip and finish" : "Skip this app", action: skip)
            }
        }
        .padding(16)
        .frame(width: 400)
        .foregroundStyle(theme[\.text])
        .font(.system(size: 13))
        .background(theme[\.base])
    }
}
