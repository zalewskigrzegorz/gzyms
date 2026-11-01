import Foundation

/// Where Gzyms keeps things. Settings live in one dotfiles-friendly folder; logs stay out of it.
public enum Paths {
    public static func configDir(env: [String: String]) -> URL {
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("gzyms")
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/gzyms")
    }

    public static func logsDir(home: URL) -> URL {
        home.appendingPathComponent("Library/Logs/Gzyms")
    }
}
