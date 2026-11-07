import Foundation
import Testing
@testable import GzymsCore

// Fixes from the M2 final review. Each failed before its fix.

@Test func lagClimbsWhileTheBarIsNotAnswering() {
    let since = Date(timeIntervalSince1970: 1000)
    #expect(displayLagMs(.notAnswering(since: since), now: since.addingTimeInterval(3.5)) == 3500)
    #expect(displayLagMs(.fresh(sampleVitals), now: t0) == 3.5)
    #expect(displayLagMs(.missing, now: t0) == nil)
}

@Test func onlyOneHolderOfTheInstanceLock() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)").path
    let first = try #require(InstanceLock(path: path))
    #expect(InstanceLock(path: path) == nil)
    first.release()
    #expect(InstanceLock(path: path) != nil)
}

// caffeinate (posix_spawn, Caffeine.swift) outlived Gzyms holding the lock's fd, and every new Gzyms said "already running"
// (2026-11-07). Close-on-exec keeps the fd out of any child.
@Test func theLockStaysOutOfChildProcesses() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)").path
    let lock = try #require(InstanceLock(path: path))
    #expect(fcntl(lock.fd, F_GETFD) & FD_CLOEXEC != 0)
}

@Test func lockRecordsTheHolderPid() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)").path
    let lock = try #require(InstanceLock(path: path))
    #expect(InstanceLock.holderPid(path: path) == getpid())
    lock.release()
    #expect(InstanceLock.holderPid(path: path) == nil)
}
