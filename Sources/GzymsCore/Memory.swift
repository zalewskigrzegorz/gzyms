import Darwin
import Foundation

/// Memory of the whole Mac: "used" as Activity Monitor counts it, plus swap.
public struct MemorySample: Equatable, Sendable {
    public static let warnAbove = 85.0

    public var used: UInt64
    public var total: UInt64
    public var swap: UInt64

    public init(used: UInt64, total: UInt64, swap: UInt64) { self.used = used; self.total = total; self.swap = swap }

    public var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    public var warn: Bool { percent > Self.warnAbove }

    /// App memory (internal minus purgeable) + wired + compressed.
    public static func usedBytes(internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
        (internalPages - min(purgeable, internalPages) + wired + compressed) * pageSize
    }

    /// One `host_statistics64` call and one sysctl: no subprocess.
    public static func read() -> MemorySample? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let rc = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard rc == KERN_SUCCESS else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let used = usedBytes(internalPages: UInt64(vm.internal_page_count), purgeable: UInt64(vm.purgeable_count),
                             wired: UInt64(vm.wire_count), compressed: UInt64(vm.compressor_page_count), pageSize: UInt64(getpagesize()))
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 ? swap.xsu_used : 0
        return MemorySample(used: min(used, total), total: total, swap: swapUsed)
    }
}
