import Foundation
import GzymsCore

/// Writes `vitals.json` once a second from the main thread. If main hangs, the file goes stale,
/// and that staleness is exactly what the HUD reads as "bar not answering".
@MainActor
final class VitalsWriter {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Gzyms/vitals.json")
    }
    private var timer: Timer?
    private let sample: () -> Vitals

    init(sample: @escaping () -> Vitals) { self.sample = sample }

    func start() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.write() } }
        t.tolerance = 0.2
        // .common: an open menu (the cat's) runs the event-tracking mode, and a default-mode timer would stop,
        // which the HUD then reports as "bar not answering".
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func write() {
        // Only while a HUD is up: a write every second forever is file churn for nothing
        // (and an event per write for any file monitor on the Mac). The lock, not the file, says a HUD is alive.
        guard InstanceLock.holderPid(path: HUD.pidFile.path) != nil else { return }
        guard let data = try? JSONEncoder().encode(sample()) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}
