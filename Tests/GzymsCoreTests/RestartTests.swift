import Foundation
import GzymsCore
import Testing

@Test func restartKickstartsOnlyTheDevJobsOwnBinary() {
    let dev = "/Users/x/Applications/Gzyms.app/Contents/MacOS/gzyms"
    #expect(restartRoute(agentProgram: dev, me: dev) == .kickstart)
    #expect(restartRoute(agentProgram: nil, me: "/Applications/Gzyms.app/Contents/MacOS/gzyms") == .relaunch)  // from the tap
    #expect(restartRoute(agentProgram: dev, me: "/Applications/Gzyms.app/Contents/MacOS/gzyms") == .relaunch)  // tap copy next to a dev plist
    #expect(restartRoute(agentProgram: nil, me: nil) == .relaunch)
}

@Test func relaunchWaitsForTheOldProcessThenOpens() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-relaunch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    // A stub `open` on PATH writes what it got, so the test opens nothing.
    let open = dir.appending(path: "open")
    try "#!/bin/sh\necho \"$@\" > \"\(dir.path)/opened\"\n".write(to: open, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)

    let old = Process()
    old.executableURL = URL(filePath: "/bin/sleep")
    old.arguments = ["0.5"]
    try old.run()
    let p = Process()
    p.executableURL = URL(filePath: "/bin/sh")
    p.arguments = relaunchArguments(pid: old.processIdentifier, bundle: "/Apps/Gzyms with space.app")
    p.environment = ["PATH": "\(dir.path):/usr/bin:/bin"]
    let start = Date()
    try p.run()
    p.waitUntilExit()
    #expect(Date().timeIntervalSince(start) > 0.3)  // waited for the old one
    #expect(try String(contentsOf: dir.appending(path: "opened"), encoding: .utf8) == "-n /Apps/Gzyms with space.app\n")
}
