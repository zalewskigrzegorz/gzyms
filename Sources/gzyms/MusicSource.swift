import AppKit
import GzymsCore

/// What plays, from `nowPlayingScript` in one long-lived osascript; media keys to steer it.
/// A reader that dies (Apple closed the door, osascript missing) comes back after 30 s, logged once per streak.
@MainActor
final class MusicSource {
    private var process: Process?
    private var buffer = Data()
    private var retry: Timer?
    private var failures = 0
    private let deliver: (NowPlayingLine) -> Void

    init(deliver: @escaping (NowPlayingLine) -> Void) { self.deliver = deliver }

    func start() {
        guard process == nil, retry == nil else { return }
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", nowPlayingScript]
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
            log("music: osascript did not start: \(error)")
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
            if let parsed = nowPlayingLine(line) { failures = 0; deliver(parsed) }
        }
    }

    private func ended(_ p: Process, status: Int32, why: String) {
        guard p === process else { return }  // stopped on purpose
        process = nil
        buffer = Data()
        deliver(.nothing)
        if failures == 0 { log("music: reader stopped (exit \(status)): \(why.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)), again in 30 s") }
        failures += 1
        let t = Timer(timeInterval: 30, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.retry = nil; self?.start() } }
        RunLoop.main.add(t, forMode: .common)
        retry = t
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
