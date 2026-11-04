import AppKit
import GzymsCore

let debugName = Notification.Name("dev.gzyms.debug")

/// `gzyms debug [notifications|keys] [--json]`: the running bar tells what it sees. It holds Full Disk Access and
/// Accessibility, this process may not, so the bar answers into a file and this reads it. No text of any notification.
@MainActor
enum DebugCommand {
    static var dir: URL { VitalsWriter.url.deletingLastPathComponent() }
    static func replyFile(_ id: String) -> URL { dir.appendingPathComponent("debug-\(id).json") }

    static func run(_ args: [String]) -> Never {
        guard let (topics, json) = debugArguments(args) else { fail("usage: gzyms debug [notifications|keys] [--json]") }
        guard DNDCommand.barRunning() else { fail("gzyms debug: Gzyms is not running") }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let file = replyFile(id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DistributedNotificationCenter.default().postNotificationName(debugName, object: debugRequest(id: id, topics: topics), userInfo: nil, deliverImmediately: true)
        // Notification Center can stall the observer's reads for seconds after a wake: 1 s per Accessibility call.
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if let data = try? Data(contentsOf: file), let report = DebugReport(wire: data) {
                try? FileManager.default.removeItem(at: file)
                if json { FileHandle.standardOutput.write(report.json() + Data("\n".utf8)) } else { print(report.text(), terminator: "") }
                exit(0)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        fail("gzyms debug: the bar did not answer in 6 s. Its main thread may be stuck: gzyms hud shows the lag.")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
