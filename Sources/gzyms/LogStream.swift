import Foundation
import GzymsCore

/// One long-running `log stream`, handing each matching `eventMessage` to the main thread. Two of them run:
/// `usernoted`'s "app X just sent a notification" (spike S1, ~5 s ahead of the Notification Center row)
/// and Control Center's camera and mic attributions.
final class LogStream: @unchecked Sendable {
    private let queue: DispatchQueue
    private let name: String
    private let filter: String
    private let deliver: @MainActor (String) -> Void
    private var buffer = Data()
    private var input: Pipe?
    private var stopped = false

    /// `filter` = the `log stream` arguments after `--style ndjson`. `name` prefixes its lines in gzyms.log.
    init(name: String, filter: String, deliver: @escaping @MainActor (String) -> Void) {
        self.name = name; self.filter = filter; self.deliver = deliver
        queue = DispatchQueue(label: "dev.gzyms.\(name)")
    }

    func start() { queue.async { self.launch() } }

    /// Closing stdin ends the wrapper, which takes `log stream` with it.
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
            /usr/bin/log stream --style ndjson \(filter) & pid=$!
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
            if chunk.isEmpty { h.readabilityHandler = nil; return }  // end of file: the stream is gone
            self?.queue.async { self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            guard let me = self else { return }
            me.queue.async {
                guard !me.stopped else { log("\(me.name): off"); return }
                log("\(me.name): log stream ended, restarting in 5 s")
                me.queue.asyncAfter(deadline: .now() + 5) { me.launch() }
            }
        }
        do { try p.run(); log("\(name): on") } catch { log("\(name): could not start log stream: \(error)") }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = obj["eventMessage"] as? String else { continue }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver(message) } }
        }
    }
}
