import AppKit
import GzymsCore

let gzymsVersion = "0.1.1"

/// `gzyms report` and Debug → Report a problem…: one zip on the Desktop with what an agent or Greg needs to look
/// into a problem. The log never holds notification titles or bodies. The config loses its secrets and personal names,
/// every file loses the home path (`ReportScrub`).
@MainActor
enum Report {
    /// The zip's path, or nil (logged) when it could not be made.
    static func make(grants: [GrantState]?) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let logs = Paths.logsDir(home: home)
        let stamp = Date().ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let dir = fm.temporaryDirectory.appendingPathComponent("gzyms-report-\(stamp)")
        let zip = home.appendingPathComponent("Desktop/gzyms-report-\(stamp).zip")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }
            if let log = try? String(contentsOf: logs.appendingPathComponent("gzyms.log"), encoding: .utf8) {
                try ReportScrub.text(log.split(separator: "\n", omittingEmptySubsequences: false).suffix(2000).joined(separator: "\n"), home: home.path)
                    .write(to: dir.appendingPathComponent("gzyms.log"), atomically: true, encoding: .utf8)
            }
            if let anomalies = try? String(contentsOf: logs.appendingPathComponent("anomalies.jsonl"), encoding: .utf8) {
                try ReportScrub.text(anomalies, home: home.path).write(to: dir.appendingPathComponent("anomalies.jsonl"), atomically: true, encoding: .utf8)
            }
            if let config = try? String(contentsOf: ThemeCommand.configFile.resolvingSymlinksInPath(), encoding: .utf8) {
                try ReportScrub.text(ReportScrub.config(config), home: home.path)
                    .write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
            }
            try about(grants: grants).write(to: dir.appendingPathComponent("about.txt"), atomically: true, encoding: .utf8)
            let ditto = Process()
            ditto.executableURL = URL(filePath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", dir.path, zip.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { log("report: ditto failed (\(ditto.terminationStatus))"); return nil }
            log("report: \(zip.lastPathComponent)")
            return zip
        } catch {
            log("report: \(error)")
            return nil
        }
    }

    private static func about(grants: [GrantState]?) -> String {
        let hyprmac = Bundle(url: URL(filePath: "/Applications/HyprMac.app"))?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        var lines = [
            "gzyms: \(gzymsVersion)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "HyprMac: \(hyprmac ?? "not found")",
            "screens: \(NSScreen.screens.map(\.localizedName).joined(separator: ", "))",
        ]
        if let grants { lines += grants.map { "\($0.grant.title): \($0.granted ? "on" : "off")" } }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The CLI: grants belong to the bar's process, so they are left out here.
    static func run() -> Never {
        guard let zip = make(grants: nil) else {
            FileHandle.standardError.write(Data("gzyms report: could not make the report, see the log\n".utf8))
            exit(1)
        }
        print(zip.path)
        exit(0)
    }
}
