import AppKit
import GzymsCore

/// What plays, from one long-lived reader: the native one (tools/media-reader, loaded into /usr/bin/perl) with the other
/// sources too, or `nowPlayingScript` in osascript when that one does not start. Media keys to steer it.
/// A reader that dies (Apple closed the door) comes back after 30 s, logged once per streak.
@MainActor
final class MusicSource {
    private var process: Process?
    private var buffer = Data()
    private var retry: Timer?
    private var failures = 0
    /// Off for the rest of the session once the native reader died before its first line.
    private var native = true
    private var gotLine = false
    private let deliver: (NowPlayingLine) -> Void

    init(deliver: @escaping (NowPlayingLine) -> Void) { self.deliver = deliver }

    func start() {
        guard process == nil, retry == nil else { return }
        let p = Process()
        if native, let reader = Bundle.main.url(forResource: "media-reader", withExtension: "dylib") {
            p.executableURL = URL(filePath: "/usr/bin/perl")
            p.arguments = ["-e", "require DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error()", reader.path]
        } else {
            if native { native = false; log("music: no media-reader.dylib in the bundle, osascript reader (Now Playing only)") }
            p.executableURL = URL(filePath: "/usr/bin/osascript")
            p.arguments = ["-l", "JavaScript", "-e", nowPlayingScript]
        }
        gotLine = false
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(d) } }
        }
        p.terminationHandler = { [weak self] p in
            let why = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let status = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended(p, status: status, why: why) } }
        }
        do {
            try p.run()
            process = p
        } catch {
            log("music: reader did not start: \(error)")
        }
    }

    func stop() {
        retry?.invalidate(); retry = nil
        let p = process
        process = nil
        p?.terminate()
        deliver(.nothing)
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[..<nl], as: UTF8.self)
            buffer.removeSubrange(...nl)
            if let parsed = nowPlayingLine(line) { failures = 0; gotLine = true; deliver(parsed) }
        }
    }

    private func ended(_ p: Process, status: Int32, why: String) {
        guard p === process else { return }  // stopped on purpose
        process = nil
        buffer = Data()
        deliver(.nothing)
        let reason = why.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
        if native && !gotLine {
            native = false
            log("music: native reader failed (exit \(status)): \(reason), back to osascript")
            start()
            return
        }
        if failures == 0 { log("music: reader stopped (exit \(status)): \(reason), again in 30 s") }
        failures += 1
        let t = Timer(timeInterval: 30, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.retry = nil; self?.start() } }
        RunLoop.main.add(t, forMode: .common)
        retry = t
    }

    /// An app with media to the front; first its window whose title holds the track, so a browser shows the film's
    /// window. shortcut: the film's tab must be the front tab of that window, Vimma's AppleScript has no tabs.
    static func jump(to bundleID: String, title: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            log("music: \(bundleID) not running, nothing to jump to"); return
        }
        // AX waits on the app: a busy browser must not hold the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            var windows: CFTypeRef?
            if AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
               let w = (windows as? [AXUIElement])?.first(where: { w in
                   var t: CFTypeRef?
                   return AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success
                       && (t as? String)?.localizedCaseInsensitiveContains(title) == true
               }) {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
            app.activate()
        }
    }

    /// The media key, as if pressed on the keyboard: macOS gives it to whatever plays.
    static func send(_ c: MediaCommand) {
        for down in [true, false] {
            let data1 = Int((c.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            e?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
