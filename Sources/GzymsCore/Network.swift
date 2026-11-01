import Darwin
import Foundation
import SystemConfiguration

public struct NetCounter: Equatable, Sendable {
    public var rx: UInt32, tx: UInt32
    public init(rx: UInt32, tx: UInt32) { self.rx = rx; self.tx = tx }
}

public enum NetKind: Sendable { case wifi, ethernet, none }

/// What the network pill and its popup show. Rates in bytes per second.
public struct NetSample: Equatable, Sendable {
    public var down: Double, up: Double
    public var kind: NetKind
    public var ip: String?
    public var tailscale: String?
    /// All traffic leaves through a Tailscale exit node.
    public var tailscaleExit: Bool
    /// "host:port" of the system HTTP(S) proxy when one is on: the "Proxyman left it on" case.
    public var proxy: String?

    public init(down: Double, up: Double, kind: NetKind, ip: String?, tailscale: String?, tailscaleExit: Bool = false, proxy: String?) {
        self.down = down; self.up = up; self.kind = kind; self.ip = ip; self.tailscale = tailscale
        self.tailscaleExit = tailscaleExit; self.proxy = proxy
    }

    /// Changes worth a bump on the pill: link type, Tailscale, exit node, proxy. Rates are not.
    public var state: String { "\(kind)|\(tailscale != nil)|\(tailscaleExit)|\(proxy ?? "")" }

    /// "30K", "1.2M", "99M": at most four characters, so the pill keeps its width.
    public static func short(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 9_950_000 { return String(format: "%.0fM", bytesPerSec / 1e6) }
        if bytesPerSec >= 999_500 { return String(format: "%.1fM", bytesPerSec / 1e6) }
        return String(format: "%.0fK", bytesPerSec / 1e3)
    }

    public static func long(_ bytesPerSec: Double) -> String {
        bytesPerSec >= 1e6 ? String(format: "%.1f MB/s", bytesPerSec / 1e6) : String(format: "%.0f KB/s", bytesPerSec / 1e3)
    }
}

/// Reads interface counters (getifaddrs), the primary interface and the system proxy (configd). No subprocess.
public struct NetSampler {
    private var last: (counters: [String: NetCounter], at: Double)?
    private var kinds: [String: NetKind] = [:]  // BSD name → kind, looked up once each
    private let store = SCDynamicStoreCreate(nil, "gzyms" as CFString, nil, nil)

    public init() {}

    public mutating func sample(now: Double) -> NetSample {
        var counters: [String: NetCounter] = [:]
        var ipv4: [String: String] = [:]
        var ifap: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifap) == 0, let first = ifap {
            for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let name = String(cString: p.pointee.ifa_name)
                guard let addr = p.pointee.ifa_addr else { continue }
                if addr.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"), let data = p.pointee.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    counters[name] = NetCounter(rx: d.ifi_ibytes, tx: d.ifi_obytes)
                } else if addr.pointee.sa_family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        ipv4[name] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    }
                }
            }
            freeifaddrs(ifap)
        }
        let r = last.map { Self.rates(prev: $0.counters, now: counters, wall: now - $0.at) } ?? (down: 0, up: 0)
        last = (counters, now)

        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) } as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String
        let proxies = store.flatMap { SCDynamicStoreCopyProxies($0) } as? [String: Any] ?? [:]
        // With an exit node the default route goes through Tailscale's utun interface.
        let exit = primary.map { $0.hasPrefix("utun") && ipv4[$0].map(Self.isTailscale) == true } ?? false
        // shortcut: behind an exit node the link is the first en* with an address; fine for one active link.
        let physical = exit ? ipv4.keys.filter { $0.hasPrefix("en") }.sorted().first : primary
        return NetSample(down: r.down, up: r.up, kind: physical.map { kind(of: $0) } ?? .none, ip: physical.flatMap { ipv4[$0] },
                         tailscale: ipv4.values.first(where: Self.isTailscale), tailscaleExit: exit, proxy: Self.proxy(from: proxies))
    }

    private mutating func kind(of bsd: String) -> NetKind {
        if let k = kinds[bsd] { return k }
        let iface = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface])?.first { SCNetworkInterfaceGetBSDName($0) as String? == bsd }
        let k: NetKind = iface.flatMap { SCNetworkInterfaceGetInterfaceType($0) } == kSCNetworkInterfaceTypeIEEE80211 ? .wifi : .ethernet
        kinds[bsd] = k
        return k
    }

    /// Wrapping deltas per interface (the counters are 32-bit); interfaces without a previous sample are skipped.
    public static func rates(prev: [String: NetCounter], now: [String: NetCounter], wall: Double) -> (down: Double, up: Double) {
        guard wall > 0 else { return (0, 0) }
        var rx = 0.0, tx = 0.0
        for (name, c) in now {
            guard let p = prev[name] else { continue }
            rx += Double(c.rx &- p.rx)
            tx += Double(c.tx &- p.tx)
        }
        return (rx / wall, tx / wall)
    }

    public static func proxy(from settings: [String: Any]) -> String? {
        for scheme in ["HTTPS", "HTTP"] where (settings["\(scheme)Enable"] as? Int) == 1 {
            if let host = settings["\(scheme)Proxy"] as? String, let port = settings["\(scheme)Port"] as? Int { return "\(host):\(port)" }
        }
        return nil
    }

    /// Tailscale hands out addresses from the CGNAT range 100.64.0.0/10.
    public static func isTailscale(_ ip: String) -> Bool {
        let o = ip.split(separator: ".").compactMap { Int($0) }
        return o.count == 4 && o[0] == 100 && (64...127).contains(o[1])
    }
}
