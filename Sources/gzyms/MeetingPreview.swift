import AVFoundation
import AppKit
import GzymsCore
import GzymsUI
import Observation
import SwiftUI

/// The window for the check before a meeting. The camera runs only while it is open.
@MainActor @Observable
final class MeetingPreview {
    var meeting: Meeting?
    var cameraID = "off"
    private(set) var session: AVCaptureSession?
    @ObservationIgnored private var panel: PreviewPanel?
    @ObservationIgnored var onJoin: (Meeting) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored private weak var model: BarModel?

    /// Without the iPhone's Continuity camera while the iPhone is banned.
    var cameras: [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external] + (model?.config.bansIPhone == true ? [] : [.continuityCamera])
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }

    var isOpen: Bool { panel?.isVisible == true }

    func show(_ m: Meeting, model: BarModel, on screen: NSScreen?) {
        meeting = m
        self.model = model
        if panel == nil {
            let p = PreviewPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "Before the meeting"
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.setAccessibilitySubrole(.floatingWindow)  // HyprMac leaves it alone
            p.contentView = NSHostingView(rootView: PreviewRoot(preview: self, model: model))
            p.onKey = { [weak self] k in self?.key(k) ?? false }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { _ in
                MainActor.assumeIsolated { [weak self] in
                    log("calendar: preview closed")
                    self?.stopCamera()
                    self?.onClose()
                }
            }
            panel = p
        }
        if cameraID == "off" || !cameras.contains(where: { $0.uniqueID == cameraID }) {
            cameraID = cameras.first?.uniqueID ?? "off"
        }
        startCamera()
        guard let p = panel else { return }
        p.setContentSize(p.contentView?.fittingSize ?? NSSize(width: 520, height: 520))
        if let f = screen?.visibleFrame { p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.midY - p.frame.height / 2)) }
        p.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.close() }

    /// true = handled. C, M, S step to the next camera, mic, speakers; T test sound; Return or o join; Esc close.
    private func key(_ k: NavKey) -> Bool {
        var nav = KeyNav(context: .preview, verbs: model?.config.verbs ?? Verbs())
        let r = nav.handle(.key(k), now: 0)
        for a in r.actions {
            switch a {
            case .choose: if let m = meeting { onJoin(m) }
            case .exit: close()
            case .preview("c"): pickCamera(Self.next(after: cameraID, in: ["off"] + cameras.map(\.uniqueID)))
            case .preview("t"): NSSound(named: "Glass")?.play()
            case .preview(let c): stepAudio(input: c == "m")
            default: break
            }
        }
        return r.swallow
    }

    /// Fresh read, not the 2 s old model: a held key outruns it. A device macOS refuses (an iPhone mic that is not
    /// reachable) is skipped, otherwise the next press picks it again and the cycle sticks on the one before.
    /// Runs on `Audio.queue`: the serial queue also keeps held presses in order, each reading what the last one set.
    private func stepAudio(input: Bool) {
        let changed: @MainActor () -> Void = { [weak self] in self?.model?.onAudioChange() }
        let banned = model?.config.bannedDevices ?? []
        Audio.queue.async {
            let kind = input ? "mic" : "speakers"
            let next = Audio.read().candidates(input: input, banned: banned)
            if next.isEmpty { log("calendar: preview \(kind) has no other device that is not banned") }
            for d in next {
                if Audio.setDefault(d.id, input: input) {
                    log("calendar: preview \(kind) \(d.name)")
                    DispatchQueue.main.async { changed() }
                    return
                }
                log("calendar: preview \(kind) \(d.name) refused, trying the next one")
            }
        }
    }

    private static func next(after current: String, in ids: [String]) -> String {
        guard !ids.isEmpty else { return current }
        let i = ids.firstIndex(of: current).map { ($0 + 1) % ids.count } ?? 0
        return ids[i]
    }

    func pickCamera(_ id: String) {
        log("calendar: preview camera \(id == "off" ? "off" : cameras.first { $0.uniqueID == id }?.localizedName ?? id)")
        cameraID = id
        startCamera()
    }

    /// Asks for the camera the first time; "off" or a refusal shows the placeholder instead.
    private func startCamera() {
        stopCamera()
        guard cameraID != "off", let device = cameras.first(where: { $0.uniqueID == cameraID }) else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in if ok { self?.startCamera() } } }
            }
            return
        case .authorized: break
        default: log("calendar: no camera access, preview shows none"); return
        }
        let s = AVCaptureSession()
        guard let input = try? AVCaptureDeviceInput(device: device), s.canAddInput(input) else { return }
        s.addInput(input)
        session = s
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }  // blocks for ~100 ms
    }

    private func stopCamera() {
        if let s = session { DispatchQueue.global(qos: .utility).async { s.stopRunning() } }
        session = nil
    }
}

/// Its keys go through `KeyNav` while it is the key window; the rest go on to its views.
private final class PreviewPanel: NSPanel {
    var onKey: (NavKey) -> Bool = { _ in false }

    override func sendEvent(_ e: NSEvent) {
        if e.type == .keyDown,
           onKey(NavKey(keyCode: Int64(e.keyCode), modified: !e.modifierFlags.intersection([.command, .control, .option]).isEmpty)) { return }
        super.sendEvent(e)
    }
}

private struct PreviewRoot: View {
    let preview: MeetingPreview
    let model: BarModel

    var body: some View {
        if let m = preview.meeting {
            let now = Date().timeIntervalSince1970
            let audio = model.audio
            MeetingPreviewView(
                title: m.title, when: AppDelegate.meetingSubtitle(m, now: now), late: now >= m.start + 60,
                session: preview.session,
                cameras: preview.cameras.map { .init(id: $0.uniqueID, name: $0.localizedName) }, camera: preview.cameraID,
                inputs: (audio?.pickable(input: true) ?? []).map { .init(id: String($0.id), name: $0.name) }, input: audio?.input.map(String.init) ?? "",
                outputs: (audio?.pickable(input: false) ?? []).map { .init(id: String($0.id), name: $0.name) }, output: audio?.output.map(String.init) ?? "",
                level: model.micLevel,
                pick: { kind, id in
                    switch kind {
                    case "camera": preview.pickCamera(id)
                    default:
                        if let dev = UInt32(id) { Audio.setDefaultAsync(dev, input: kind == "input") { _ in model.onAudioChange() } }
                    }
                },
                testSound: { NSSound(named: "Glass")?.play() },
                join: { preview.onJoin(m) },
                cancel: { preview.close() })
                .themed(model.config.theme)
                .environment(\.controlActiveState, .key)
        }
    }
}
