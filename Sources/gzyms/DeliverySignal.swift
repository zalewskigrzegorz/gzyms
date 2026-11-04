import Foundation
import GzymsCore

/// The instant "app X just sent a notification" from `usernoted`'s log (spike S1): one long-running
/// `log stream`, no text, ~5 s ahead of the Notification Center row.
final class DeliverySignal: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.gzyms.signal")
    private let deliver: @MainActor (String) -> Void
    private var buffer = Data()
    private var input: Pipe?
    private var stopped = false

    init(deliver: @escaping @MainActor (String) -> Void) { self.deliver = deliver }

    func start() { queue.async { self.launch() } }

    /// `[notifications] signal` turned off: closing stdin ends the wrapper, which takes `log stream` with it.
    func stop() {
        queue.async {
            self.stopped = true
            try? self.input?.fileHandleForWriting.close()
            self.input = nil
        }
    }

    private func launch() {
        guard !stopped else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // `log` does not read stdin, so a wrapper does: when Gzyms dies, the pipe closes and the stream goes with it.
        p.arguments = ["-c", """
            /usr/bin/log stream --process usernoted --style ndjson --predicate 'eventMessage BEGINSWITH "Delivering"' & pid=$!
            read _; kill $pid
            """]
        let out = Pipe()
        p.standardOutput = out
        let input = Pipe()
        p.standardInput = input
        self.input = input
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            self?.queue.async { self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            guard let me = self else { return }
            me.queue.async {
                guard !me.stopped else { log("signal: off"); return }
                log("signal: log stream ended, restarting in 5 s")
                me.queue.asyncAfter(deadline: .now() + 5) { me.launch() }
            }
        }
        do { try p.run(); log("signal: on") } catch { log("signal: could not start log stream: \(error)") }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = obj["eventMessage"] as? String, let app = deliveredApp(message) else { continue }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver(app) } }
        }
    }
}
