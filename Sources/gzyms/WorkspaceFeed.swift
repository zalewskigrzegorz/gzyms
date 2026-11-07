import AppKit
import GzymsCore

/// `gzyms workspaces refresh`, for AeroSpace's `exec-on-workspace-change`.
let workspacesRefreshName = Notification.Name("dev.gzyms.workspaces")
let aerospaceBundleID = "bobko.aerospace"

/// Workspaces from AeroSpace or macOS Spaces. HyprMac has its own `StateWatcher`. A slow poll catches windows that open
/// and close, a nudge on each switch (AeroSpace's callback, the Spaces notification) makes the switch itself instant.
@MainActor
final class WorkspaceFeed {
    private let onChange: (HyprMacState?) -> Void
    private(set) var source: WorkspaceSource?
    private var timer: Timer?
    private var cancels: [() -> Void] = []
    /// One AeroSpace read at a time. shortcut: a CLI call that never returns stops the polling; add a timeout if that shows up.
    private var reading = false

    init(onChange: @escaping (HyprMacState?) -> Void) { self.onChange = onChange }

    func run(_ s: WorkspaceSource) {
        guard s != source else { return }
        stop()
        source = s
        guard s == .aerospace || s == .spaces else { return }
        log("workspaces: from \(s.rawValue)")
        refresh()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let refreshNow: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        let dnc = DistributedNotificationCenter.default()
        let token = dnc.addObserver(forName: workspacesRefreshName, object: nil, queue: .main, using: refreshNow)
        cancels.append { dnc.removeObserver(token) }
        if s == .spaces {
            let nc = NSWorkspace.shared.notificationCenter
            let t = nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: refreshNow)
            cancels.append { nc.removeObserver(t) }
        }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        cancels.forEach { $0() }; cancels = []
        onChange(nil)
    }

    func refresh() {
        switch source {
        case .aerospace:
            guard !reading else { return }
            reading = true
            DispatchQueue.global(qos: .utility).async {
                let ws = Self.aerospace(["list-workspaces", "--all", "--json", "--format", aerospaceWorkspaceFormat])
                let wins = Self.aerospace(["list-windows", "--all", "--json", "--format", aerospaceWindowFormat])
                let state = ws.flatMap { aerospaceState(workspaces: $0, windows: wins ?? Data()) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.reading = false
                        if self.source == .aerospace { self.onChange(state) }
                    }
                }
            }
        case .spaces: onChange(Spaces.read())
        default: break
        }
    }

    /// A click on workspace `n`. AeroSpace switches by name. Spaces press the user's "Switch to Desktop N" shortcut,
    /// else open Mission Control: switching directly needs code in the Dock (SIP off).
    func select(_ n: Int, state: HyprMacState?) {
        switch source {
        case .aerospace:
            let name = state?.workspaces.first { $0.id == n }?.label ?? "\(n)"
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.aerospace(["workspace", name])
                DispatchQueue.main.async { MainActor.assumeIsolated { self.refresh() } }
            }
        case .spaces:
            let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
            if let key = desktopShortcut(hotkeys, desktop: n) {
                let src = CGEventSource(stateID: .hidSystemState)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: down)
                    e?.flags = CGEventFlags(rawValue: key.flags)
                    e?.post(tap: .cghidEventTap)
                }
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            }
        default: break
        }
    }

    /// The CLI comes from Homebrew (or nix), never inside the app bundle. A GUI app's PATH has no /opt/homebrew/bin.
    nonisolated static let aerospaceBinary: URL? = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/run/current-system/sw/bin", NSHomeDirectory() + "/.nix-profile/bin"] + path
        return dirs.map { URL(fileURLWithPath: $0).appendingPathComponent("aerospace") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    nonisolated static func aerospace(_ args: [String]) -> Data? {
        guard let bin = aerospaceBinary else { return nil }
        let p = Process()
        p.executableURL = bin
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}

/// macOS Spaces through the private CGS calls Mission Control uses. Read only: they still answer on macOS 27 without SIP changes.
@MainActor
private enum Spaces {
    typealias ConnFn = @convention(c) () -> Int32
    typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias ActiveFn = @convention(c) (Int32) -> UInt64
    typealias ForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let lib = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    private static func sym<T>(_ name: String, _: T.Type) -> T? { dlsym(lib, name).map { unsafeBitCast($0, to: T.self) } }
    private static let connection = sym("CGSMainConnectionID", ConnFn.self)
    private static let copyDisplaySpaces = sym("CGSCopyManagedDisplaySpaces", CopyFn.self)
    private static let activeSpace = sym("CGSGetActiveSpace", ActiveFn.self)
    private static let spacesForWindows = sym("CGSCopySpacesForWindows", ForWindowsFn.self)

    /// nil = a call is gone in this macOS: the bar then shows one desktop.
    static func read() -> HyprMacState? {
        guard let connection, let copyDisplaySpaces, let activeSpace, let spacesForWindows,
              let raw = copyDisplaySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let cid = connection()
        let me = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            if let id = app.bundleIdentifier { apps[app.processIdentifier] = id }
        }
        let infos = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var windows: [(bundleID: String, spaces: [UInt64])] = []
        for w in infos where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, let app = apps[pid], let id = w[kCGWindowNumber as String] as? Int,
                  let spaces = spacesForWindows(cid, 7, [id] as CFArray)?.takeRetainedValue() as? [UInt64], !spaces.isEmpty else { continue }
            windows.append((app, spaces))
        }
        return spacesState(displays: spaceDisplays(raw), screenNames: screenNames(), active: activeSpace(cid), windows: windows)
    }

    /// "Main" (one set of Spaces for all displays) is the menu bar screen, the rest go by display UUID.
    private static func screenNames() -> [String: String] {
        var out: [String: String] = [:]
        if let main = NSScreen.screens.first { out["Main"] = main.localizedName }
        for s in NSScreen.screens {
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue(),
                  let text = CFUUIDCreateString(nil, uuid) as String? else { continue }
            out[text] = s.localizedName
        }
        return out
    }
}

/// `gzyms workspaces refresh`: AeroSpace runs it on each switch, so the bar follows at once instead of on the next poll.
@MainActor
enum WorkspacesCommand {
    static func run(_ args: [String]) -> Never {
        guard args == ["refresh"] else {
            FileHandle.standardError.write(Data("gzyms workspaces: refresh\n".utf8))
            exit(1)
        }
        // Quiet when the bar is not running: AeroSpace calls this on every switch.
        if DNDCommand.barRunning() {
            DistributedNotificationCenter.default().postNotificationName(workspacesRefreshName, object: nil, userInfo: nil, deliverImmediately: true)
        }
        exit(0)
    }
}
