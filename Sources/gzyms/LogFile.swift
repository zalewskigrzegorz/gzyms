import Foundation
import GzymsCore

/// The bar's own `gzyms.log` when nothing else keeps its stderr (`ownsLogFile`). Only the bar process calls `take`:
/// CLI commands and the HUD keep their stderr, so a command run in a terminal still prints there.
@MainActor
enum LogFile {
    static let url = Paths.logsDir(home: FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("gzyms.log")
    private static var owned = false

    static func take() {
        var st = stat()
        guard fstat(STDERR_FILENO, &st) == 0, ownsLogFile(stderrMode: st.st_mode) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        owned = true
        _ = moveIfBig()
        reopen()
    }

    /// Once a day: a big log moves to `gzyms.log.1` and stderr starts a fresh file.
    static func rotateIfBig() {
        guard owned, moveIfBig() else { return }
        reopen()
    }

    private static func moveIfBig() -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        guard size >= logCap else { return false }
        let old = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        return (try? FileManager.default.moveItem(at: url, to: old)) != nil
    }

    private static func reopen() {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        dup2(fd, STDERR_FILENO)
        close(fd)
    }
}
