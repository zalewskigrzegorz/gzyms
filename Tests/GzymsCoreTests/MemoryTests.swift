import Testing
@testable import GzymsCore

@Test func usedMemoryLikeActivityMonitor() {
    // App memory (internal minus purgeable) + wired + compressed, in pages.
    let used = MemorySample.usedBytes(internalPages: 1000, purgeable: 100, wired: 200, compressed: 50, pageSize: 16384)
    #expect(used == 1150 * 16384)
}

@Test func memoryPercentAndWarn() {
    let m = MemorySample(used: 30 << 30, total: 36 << 30, swap: 0)
    #expect(Int(m.percent) == 83)
    #expect(!m.warn)
    #expect(MemorySample(used: 31 << 30, total: 36 << 30, swap: 0).warn)
}

@Test func memoryOfThisMac() throws {
    let m = try #require(MemorySample.read())
    #expect(m.total > 0)
    #expect(m.used > 0 && m.used <= m.total)
}
