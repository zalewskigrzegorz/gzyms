import Testing
@testable import GzymsCore

@Test func ratesFromCounterDeltas() {
    let prev = ["en0": NetCounter(rx: 1000, tx: 500)]
    let now = ["en0": NetCounter(rx: 3000, tx: 900), "en5": NetCounter(rx: 10, tx: 10)]
    let r = NetSampler.rates(prev: prev, now: now, wall: 2)
    #expect(r.down == 1000)  // en5 is new: no previous sample, not counted
    #expect(r.up == 200)
}

@Test func ratesSurviveThirtyTwoBitWrap() {
    // if_data counters are 32-bit and wrap every 4 GB.
    let r = NetSampler.rates(prev: ["en0": NetCounter(rx: .max - 99, tx: 0)], now: ["en0": NetCounter(rx: 100, tx: 0)], wall: 1)
    #expect(r.down == 200)
}

@Test func shortRateFormat() {
    #expect(NetSample.short(0) == "0K")
    #expect(NetSample.short(30_400) == "30K")
    #expect(NetSample.short(1_234_000) == "1.2M")
    #expect(NetSample.short(98_700_000) == "99M")
}

@Test func proxyFromSystemSettings() {
    #expect(NetSampler.proxy(from: [:]) == nil)
    #expect(NetSampler.proxy(from: ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9090]) == "127.0.0.1:9090")
    #expect(NetSampler.proxy(from: ["HTTPSEnable": 1, "HTTPSProxy": "proxy.local", "HTTPSPort": 8443]) == "proxy.local:8443")
    #expect(NetSampler.proxy(from: ["HTTPEnable": 0, "HTTPProxy": "127.0.0.1", "HTTPPort": 9090]) == nil)
}

@Test func tailscaleAddressRange() {
    #expect(NetSampler.isTailscale("100.90.5.9"))
    #expect(NetSampler.isTailscale("100.64.0.1"))
    #expect(!NetSampler.isTailscale("100.128.0.1"))
    #expect(!NetSampler.isTailscale("192.168.1.23"))
}

@Test func networkOfThisMac() {
    var s = NetSampler()
    let first = s.sample(now: 0)
    #expect(first.down == 0)  // no rate on the first sample
}
