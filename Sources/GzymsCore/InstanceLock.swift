import Darwin
import Foundation

/// One HUD at a time, by a kernel lock on the pid file rather than by trusting the pid in it:
/// the lock dies with its process, so a stale file or a reused pid can never point at the wrong process.
public final class InstanceLock: @unchecked Sendable {
    private var fd: Int32

    /// nil = someone else holds it.
    public init?(path: String) {
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        ftruncate(fd, 0)
        let pid = Array("\(getpid())".utf8)
        _ = pid.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        self.fd = fd
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit { release() }

    /// The pid of the live holder, or nil when nobody holds the lock.
    public static func holderPid(path: String) -> Int32? {
        if let probe = InstanceLock(path: path) { probe.release(); return nil }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// What the HUD shows as the current lag: while the bar is not answering, the hang so far.
public func displayLagMs(_ state: VitalsState, now: Date) -> Double? {
    switch state {
    case .fresh(let v): v.lagMs
    case .notAnswering(let since): now.timeIntervalSince(since) * 1000
    case .missing: nil
    }
}
