import Foundation

/// A mark ("Flag this moment" in the palette): a note typed when something looked off, with the log lines around it copied in,
/// because `gzyms.log` rotates and those lines would be gone by the time someone looks.
public enum Marks {
    /// Seconds of log before the palette opened.
    public static let lookBack: TimeInterval = 5 * 60

    /// `marks/2026-11-17T18-38-12Z.txt`: sorts by time, no colons for Finder.
    public static func fileName(_ openedAt: Date) -> String {
        openedAt.ISO8601Format().replacingOccurrences(of: ":", with: "-") + ".txt"
    }

    /// The note, when it was made, then each log's lines from `lookBack` before `openedAt` up to `now`.
    public static func text(note: String, openedAt: Date, now: Date, logs: [(name: String, text: String)]) -> String {
        let from = (openedAt - lookBack).ISO8601Format(), to = now.ISO8601Format()
        var out = "note: \(note)\nopened: \(openedAt.ISO8601Format())\nsaved: \(to)\n"
        for log in logs {
            let lines = log.text.split(separator: "\n").filter { line in
                guard let ts = timestamp(line) else { return false }
                return ts >= from && ts <= to  // ISO 8601 in UTC sorts as text
            }
            out += "\n== \(log.name) (\(lines.count) lines)\n" + lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        }
        return out
    }

    /// The first `2026-11-17T18:38:12Z` in a line: at the start in gzyms.log, in `"ts"` in anomalies.jsonl.
    static func timestamp(_ line: Substring) -> String? {
        line.firstMatch(of: /\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/).map { String($0.output) }
    }
}
