import Darwin

/// Cumulative CPU ticks of the whole Mac, all cores together.
public struct CPUTicks: Equatable, Sendable {
    public var user, system, idle, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// System-wide CPU load from one `host_statistics` call: no subprocess, cheap enough for every 2 s.
public enum SystemCPU {
    public static let hot = 80.0

    public static func ticks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard rc == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)
    }

    /// Busy share between two samples. Wrapping subtraction, because the counters are 32-bit.
    public static func percent(prev: CPUTicks, now: CPUTicks) -> Double {
        let busy = Double((now.user &- prev.user) &+ (now.system &- prev.system) &+ (now.nice &- prev.nice))
        let idle = Double(now.idle &- prev.idle)
        return busy + idle > 0 ? busy / (busy + idle) * 100 : 0
    }
}
