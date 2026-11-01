import AVFoundation
import AppKit
import GzymsCore
import SwiftUI

/// The check before a meeting (spec: Plugin Calendar): camera, microphone with its level, speakers with a test
/// sound, then Join. The meeting app picks its own camera; the mic and speakers are set as the macOS defaults.
public struct MeetingPreviewView: View {
    public struct Choice: Hashable, Sendable {
        public var id: String, name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    let title: String, when: String, late: Bool
    let session: AVCaptureSession?
    let cameras: [Choice], camera: String
    let inputs: [Choice], input: String
    let outputs: [Choice], output: String
    let level: Double
    let pick: (_ kind: String, _ id: String) -> Void  // "camera" | "input" | "output"
    let testSound: () -> Void
    let join: () -> Void
    let cancel: () -> Void
    @Environment(\.theme) private var theme

    public init(title: String, when: String, late: Bool, session: AVCaptureSession?, cameras: [Choice], camera: String,
                inputs: [Choice], input: String, outputs: [Choice], output: String, level: Double,
                pick: @escaping (String, String) -> Void, testSound: @escaping () -> Void, join: @escaping () -> Void,
                cancel: @escaping () -> Void) {
        self.title = title; self.when = when; self.late = late; self.session = session
        self.cameras = cameras; self.camera = camera; self.inputs = inputs; self.input = input
        self.outputs = outputs; self.output = output; self.level = level
        self.pick = pick; self.testSound = testSound; self.join = join; self.cancel = cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: "video.fill").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(when).font(.system(size: 13, weight: late ? .semibold : .regular)).foregroundStyle(late ? theme[\.red] : theme[\.overlay])
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(theme[\.surface])
                if let session, camera != "off" {
                    CameraLayer(session: session).clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Label("Camera off", systemImage: "video.slash").foregroundStyle(theme[\.overlay])
                }
            }
            .frame(height: 240)
            row("Camera", "video", key: "C") {
                picker(camera, [Choice(id: "off", name: "Off")] + cameras) { pick("camera", $0) }
            }
            row("Microphone", "mic", key: "M") {
                picker(input, inputs) { pick("input", $0) }
                LevelBar(level: level).frame(width: 90, height: 6)
            }
            row("Speakers", "speaker.wave.2", key: "S") {
                picker(output, outputs) { pick("output", $0) }
                Button("Test", action: testSound)
                KeyCap("T")
            }
            Text("The mic and speakers become the macOS defaults. The meeting app picks its own camera.")
                .font(.system(size: 11)).foregroundStyle(theme[\.overlay])
            HStack(spacing: 8) {
                Spacer()
                KeyCap("esc")
                Button("Not now", action: cancel).keyboardShortcut(.cancelAction)
                KeyCap("↩")
                Button("Join", action: join).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .foregroundStyle(theme[\.text])
        .background(theme[\.base])
    }

    private func row<C: View>(_ title: String, _ symbol: String, key: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) { KeyCap(key); Label(title, systemImage: symbol) }.frame(width: 140, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func picker(_ value: String, _ options: [Choice], set: @escaping (String) -> Void) -> some View {
        Picker("", selection: Binding(get: { value }, set: set)) {
            ForEach(options, id: \.id) { Text($0.name).tag($0.id) }
        }
        .labelsHidden().pickerStyle(.menu).frame(width: 220)
    }
}

private struct KeyCap: View {
    let key: String
    @Environment(\.theme) private var theme
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(.system(size: 11, weight: .bold)).foregroundStyle(theme[\.text])
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme[\.surface]))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme[\.overlay].opacity(0.6), lineWidth: 1))
    }
}

private struct LevelBar: View {
    let level: Double
    @Environment(\.theme) private var theme
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme[\.surface])
                Capsule().fill(theme[\.green]).frame(width: g.size.width * min(1, max(0, level)))
            }
        }
    }
}

/// The capture session's picture, drawn by Core Animation.
private struct CameraLayer: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v.layer as? AVCaptureVideoPreviewLayer)?.session = session }
}
