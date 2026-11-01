import Foundation
import IOKit

/// One read of `AppleSmartBattery`. Watts: `batteryW` is + when charging, − when draining.
public struct BatterySample: Equatable, Sendable {
    public var percent: Int
    public var plugged: Bool
    public var charging: Bool
    public var adapterW: Int?
    public var systemW: Double?
    public var batteryW: Double

    /// macOS says it stopped charging on purpose (full, or held at the 80% charge limit).
    public var fullyCharged = false
    /// macOS's own estimate in minutes: to empty on battery, to full while charging. nil = still estimating.
    public var minutesLeft: Int?

    /// "5:55h", as the SketchyBar widget showed it.
    public var timeLeft: String? { minutesLeft.map { String(format: "%d:%02dh", $0 / 60, $0 % 60) } }

    /// On the adapter and full or held at the limit: macOS lets the battery drift a little, which is not draining.
    public var full: Bool { plugged && (fullyCharged || percent >= 95) }
    public var draining: Bool { batteryW < -0.5 && !full }

    public init(percent: Int, plugged: Bool, charging: Bool, adapterW: Int?, systemW: Double?, batteryW: Double) {
        self.percent = percent; self.plugged = plugged; self.charging = charging
        self.adapterW = adapterW; self.systemW = systemW; self.batteryW = batteryW
    }

    public init?(props: [String: Any]) {
        guard let cur = props["CurrentCapacity"] as? Int, let max = props["MaxCapacity"] as? Int, max > 0 else { return nil }
        // Amperage can arrive as an unsigned 64-bit pattern (ioreg prints 1844…); int64Value restores the sign.
        let mV = Double(props["Voltage"] as? Int ?? 0), mA = Double((props["Amperage"] as? NSNumber)?.int64Value ?? 0)
        self.init(percent: cur * 100 / max, plugged: props["ExternalConnected"] as? Bool ?? false,
                  charging: props["IsCharging"] as? Bool ?? false,
                  adapterW: (props["AdapterDetails"] as? [String: Any])?["Watts"] as? Int,
                  systemW: ((props["PowerTelemetryData"] as? [String: Any])?["SystemLoad"] as? Int).map { Double($0) / 1000 },
                  batteryW: mV * mA / 1_000_000)
        fullyCharged = props["FullyCharged"] as? Bool ?? false
        let minutes = props[plugged ? "AvgTimeToFull" : "AvgTimeToEmpty"] as? Int
        minutesLeft = minutes.flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }  // 65535 = "calculating"
    }

    /// IOKit registry read: no subprocess. nil on a Mac without a battery.
    public static func read() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatterySample(props: dict)
    }
}

public enum BatteryWarning: Sendable { case chargerTooWeak, low }

/// Plugged in yet draining for `patience` seconds = the charger cannot keep up; on battery at `lowAt`% or less = low.
public struct BatteryWatch: Sendable {
    public static let patience = 120.0, lowAt = 20
    private var drainingSince: Double?

    public init() {}

    public mutating func update(_ b: BatterySample, now: Double) -> BatteryWarning? {
        if !b.plugged { drainingSince = nil; return b.percent <= Self.lowAt ? .low : nil }
        guard b.draining else { drainingSince = nil; return nil }
        let since = drainingSince ?? now
        drainingSince = since
        return now - since >= Self.patience ? .chargerTooWeak : nil
    }
}
