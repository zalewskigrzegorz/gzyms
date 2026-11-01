import Foundation

public struct ProcessCPU: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var percent: Double
    public init(pid: Int32, name: String, percent: Double) { self.pid = pid; self.name = name; self.percent = percent }
}

/// The busiest processes, sampled only while the CPU popup is open.
public enum TopProcesses {
    /// CPU seconds and name of every process, from one `ps` run. `ps` is setuid root, so it also sees
    /// root daemons (WindowServer, coreaudiod) that `proc_pid_rusage` refuses to us. Not kernel_task.
    /// A subprocess every 2 s is fine only because it runs while the popup is open, off the main thread.
    public static func snapshot() -> [Int32: (cpu: Double, name: String)] {
        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-A", "-o", "pid=,time=,comm="]
        let out = Pipe()
        ps.standardOutput = out
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return parse(ps: String(decoding: data, as: UTF8.self))
    }

    /// Lines of `pid time comm`, time as `[h:]m:ss.ss`.
    public static func parse(ps: String) -> [Int32: (cpu: Double, name: String)] {
        var out: [Int32: (cpu: Double, name: String)] = [:]
        for line in ps.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, let pid = Int32(f[0]) else { continue }
            let parts = f[1].split(separator: ":").map { Double($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { continue }
            let cpu = parts.reduce(0) { $0 * 60 + $1! }
            out[pid] = (cpu, String(f[2].split(separator: "/").last ?? f[2]))
        }
        return out
    }

    /// Percent of one core, as Activity Monitor shows it (Greg, 2026-10-31): a process stuck on a core reads 100%.
    public static func top(prev: [Int32: Double], now: [Int32: Double], wall: Double, count: Int) -> [(pid: Int32, percent: Double)] {
        guard wall > 0 else { return [] }
        let busy: [(pid: Int32, percent: Double)] = now.compactMap { pid, cpu in
            guard let before = prev[pid], cpu > before else { return nil }
            return (pid, (cpu - before) / wall * 100)
        }
        return Array(busy.sorted { $0.percent > $1.percent }.prefix(count))
    }
}
