import Foundation

/// What leaves the Mac in a report: the config without secrets or personal names, text without the home path or the
/// sites a browser tab played.
public enum ReportScrub {
    /// Keys whose value is a secret (phone push) or names something personal (files, calendars, devices).
    static let hidden: Set<String> = ["url", "pushover_user", "pushover_token", "token", "password", "secret", "topic",
                                      "files", "skip", "banned"]
    static let mark = "\"<hidden>\""

    public static func config(_ toml: String) -> String {
        var out: [String] = []
        var inArray = false
        for line in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            if inArray {  // the rest of a hidden multi-line array
                if line.contains("]") { inArray = false }
                continue
            }
            guard let eq = line.firstIndex(of: "="),
                  hidden.contains(line[..<eq].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            else { out.append(String(line)); continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") && !value.contains("]") { inArray = true }
            out.append(line[..<eq] + "= " + mark)
        }
        return out.joined(separator: "\n")
    }

    /// The user name in the home path, and the site in `media: <host>:` lines.
    public static func text(_ s: String, home: String) -> String {
        let site = /( media: )[A-Za-z0-9.-]+\.[A-Za-z]{2,}:/
        return s.replacingOccurrences(of: home, with: "~").replacing(site) { "\($0.output.1)<site>:" }
    }
}
