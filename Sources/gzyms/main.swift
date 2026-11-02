import AppKit
import GzymsCore

let args = expandShortFlags(Array(CommandLine.arguments.dropFirst()))[...]
/// Held for the bar's whole life: the kernel drops it when the process ends.
var barLock: InstanceLock?

if let topic = helpTopic(Array(args)) {
    guard let text = helpText(topic) else {
        FileHandle.standardError.write(Data((cliProblem([topic]) ?? "gzyms: no command \"\(topic)\"\n").utf8))
        exit(1)
    }
    print(text, terminator: "")
    exit(0)
}

if let problem = cliProblem(Array(args)) {
    FileHandle.standardError.write(Data(problem.utf8))
    exit(1)
}

if args.contains("--version") {
    print("gzyms \(gzymsVersion)")
    exit(0)
}

if args.first == "theme" { ThemeCommand.run(args.dropFirst().first) }
if args.first == "notify" { NotifyCommand.run(Array(args.dropFirst())) }
if args.first == "settings" { SettingsCommand.run(args.dropFirst().first) }
if args.first == "keys" { KeysCommand.run(args.dropFirst().first) }
if args.first == "dnd" { DNDCommand.run(Array(args.dropFirst())) }
if args.first == "report" { Report.run() }
if args.first == "completions" { CompletionsCommand.run(Array(args.dropFirst())) }
if args.first == "message" { MessageCommand.run(args.dropFirst().first) }
if args.first == "meeting-test" { MeetingTestCommand.run(args.dropFirst().first) }
if args.first == "plugin" { PluginCommand.run(Array(args.dropFirst())) }
if args.first == "skill" { SkillCommand.run(Array(args.dropFirst())) }
if args.first == "set" || args.first == "unset" { SetCommand.run(Array(args.dropFirst()), remove: args.first == "unset") }

let app = NSApplication.shared
let delegate: NSApplicationDelegate
if args.first == "hud" {
    if ProcessInfo.processInfo.environment[HUD.detachedEnv] != "1" {
        // A second `gzyms hud` closes the running HUD instead of opening another.
        if HUD.toggleOff() { exit(0) }
        HUD.detachFromTerminal()
    }
    HUD.becomeDetached()
    delegate = HUDController()
} else {
    // Started by hand or by Sparkle after an update, while install-dev.sh's login item runs this same binary:
    // hand over to launchd, which keeps the log and brings the bar back after a crash.
    let agent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/dev.gzyms.plist")
    let fromLaunchd = ProcessInfo.processInfo.environment["GZYMS_LAUNCHD"] == "1"
    unsetenv("GZYMS_LAUNCHD")  // Sparkle's relaunch is a child of this process and would inherit it
    if !fromLaunchd,
       let plist = NSDictionary(contentsOf: agent), let program = (plist["ProgramArguments"] as? [String])?.first,
       let me = Bundle.main.executablePath,
       URL(fileURLWithPath: program).resolvingSymlinksInPath() == URL(fileURLWithPath: me).resolvingSymlinksInPath() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "gui/\(getuid())/dev.gzyms"]
        if (try? p.run()) != nil { p.waitUntilExit(); if p.terminationStatus == 0 { exit(0) } }
    }
    // One bar at a time, before any plugin, window or permission prompt. Exit 0, or launchd's KeepAlive would retry.
    let pidFile = HUD.pidFile.deletingLastPathComponent().appendingPathComponent("gzyms.pid")
    try? FileManager.default.createDirectory(at: pidFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let lock = InstanceLock(path: pidFile.path) else {
        let pid = InstanceLock.holderPid(path: pidFile.path).map { ", pid \($0)" } ?? ""
        FileHandle.standardError.write(Data("gzyms is already running\(pid)\n".utf8))
        exit(0)
    }
    barLock = lock
    delegate = AppDelegate()
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
