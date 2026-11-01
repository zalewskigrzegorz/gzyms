import Testing
import Foundation
@testable import GzymsCore

@Test func batteryFromIOKitProperties() throws {
    let props: [String: Any] = [
        "CurrentCapacity": 78, "MaxCapacity": 100, "ExternalConnected": true, "IsCharging": false,
        "Voltage": 13000, "Amperage": -1077,  // mV, mA: draining ~14 W
        "AdapterDetails": ["Watts": 30], "PowerTelemetryData": ["SystemLoad": 44000],
    ]
    let b = try #require(BatterySample(props: props))
    #expect(b.percent == 78)
    #expect(b.plugged)
    #expect(b.adapterW == 30)
    #expect(b.systemW == 44)
    #expect(Int(b.batteryW.rounded()) == -14)
}

@Test func unsignedAmperageKeepsItsSign() throws {
    let props: [String: Any] = ["CurrentCapacity": 50, "MaxCapacity": 100, "Voltage": 12000,
                                "Amperage": NSNumber(value: UInt64(bitPattern: -1000))]
    #expect(try #require(BatterySample(props: props)).batteryW == -12)
}

@Test func timeLeftFromMacOSEstimate() throws {
    let base: [String: Any] = ["CurrentCapacity": 90, "MaxCapacity": 100, "AvgTimeToEmpty": 355, "AvgTimeToFull": 65535]
    let onBattery = try #require(BatterySample(props: base.merging(["ExternalConnected": false]) { $1 }))
    #expect(onBattery.timeLeft == "5:55h")
    let charging = try #require(BatterySample(props: base.merging(["ExternalConnected": true]) { $1 }))
    #expect(charging.timeLeft == nil)  // 65535: still estimating
}

@Test func noBatteryIsNil() {
    #expect(BatterySample(props: [:]) == nil)
}

@Test func drainingWhilePluggedWarnsOnlyAfterTwoMinutes() {
    let drain = BatterySample(percent: 78, plugged: true, charging: false, adapterW: 30, systemW: 44, batteryW: -14)
    var w = BatteryWatch()
    #expect(w.update(drain, now: 0) == nil)
    #expect(w.update(drain, now: 119) == nil)
    #expect(w.update(drain, now: 120) == .chargerTooWeak)
    // A moment of charging resets the clock: a short spike must not alarm.
    let ok = BatterySample(percent: 78, plugged: true, charging: true, adapterW: 30, systemW: 10, batteryW: 15)
    #expect(w.update(ok, now: 121) == nil)
    #expect(w.update(drain, now: 200) == nil)
}

@Test func fullOnTheAdapterIsNotDraining() {
    // Greg, 2026-10-31: "draining" at 100% on the cable is noise.
    let full = BatterySample(percent: 100, plugged: true, charging: false, adapterW: 30, systemW: 8, batteryW: -1.2)
    #expect(full.full)
    #expect(!full.draining)
    var w = BatteryWatch()
    #expect(w.update(full, now: 0) == nil)
    #expect(w.update(full, now: 500) == nil)
}

@Test func heldAtChargeLimitIsNotDraining() throws {
    let props: [String: Any] = ["CurrentCapacity": 80, "MaxCapacity": 100, "ExternalConnected": true, "FullyCharged": true,
                                "Voltage": 13000, "Amperage": -100]
    #expect(try !#require(BatterySample(props: props)).draining)
}

@Test func lowOnBatteryWarnsAtOnce() {
    var w = BatteryWatch()
    let low = BatterySample(percent: 20, plugged: false, charging: false, adapterW: nil, systemW: 8, batteryW: -8)
    #expect(w.update(low, now: 0) == .low)
    let fine = BatterySample(percent: 21, plugged: false, charging: false, adapterW: nil, systemW: 8, batteryW: -8)
    #expect(w.update(fine, now: 1) == nil)
}

@Test func batteryOfThisMac() {
    // Laptops have one; a Mac mini gives nil, both are fine.
    if let b = BatterySample.read() { #expect((0...100).contains(b.percent)) }
}
