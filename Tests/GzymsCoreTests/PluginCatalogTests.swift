import Foundation
import Testing
@testable import GzymsCore

@Test func catalogManifestsParseWithTheirOptions() throws {
    for c in pluginCatalog {
        let m = try pluginManifest(toml: c.manifest, folder: c.name).get()
        #expect(!m.options.isEmpty)
    }
}

@Test func pluginNoteOwnerReadsTheFolderBeforeTheColon() {
    #expect(pluginNoteOwner("plugin:log-watcher:error-1", plugins: ["log", "log-watcher"])! == ("log-watcher", "error-1"))
    #expect(pluginNoteOwner("plugin:log:watcher:x", plugins: ["log", "log-watcher"])! == ("log", "watcher:x"))
    #expect(pluginNoteOwner("plugin:gone:x", plugins: ["agents"]) == nil)
    #expect(pluginNoteOwner("meeting-1", plugins: ["agents"]) == nil)
}

/// Runs the real script against a fake tuios: a new "waits for you" and a finished run notify, the first look does not.
@Test(arguments: ["live", "poll"]) func agentsNotifyWhenOneWaitsOrEnds(source: String) throws {
    let ag = try #require(pluginCatalog.first { $0.name == "agents" })
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-ag-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appending(path: "plugin.sh"), fake = dir.appending(path: "tuios"), state = dir.appending(path: "state.json")
    let events = dir.appending(path: "events")
    try ag.script.write(to: script, atomically: true, encoding: .utf8)
    try Data().write(to: events)
    // subscribe = every line added to the events file; anything else = the agent list.
    try "#!/bin/bash\n[ \"$1\" = subscribe ] && exec tail -n 0 -F '\(events.path)'\ncat '\(state.path)'\n"
        .write(to: fake, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    func agents(_ a: [(String, String, Bool)]) throws {
        let rows = a.map { "{\"window_id\":\"\($0.0)\",\"session\":\"s\",\"state\":\"\($0.1)\",\"needs_you\":\($0.2),\"name\":\"\($0.0)\",\"message\":\"\"}" }
        try "{\"agents\":[\(rows.joined(separator: ","))]}".write(to: state, atomically: true, encoding: .utf8)
        let h = try FileHandle(forWritingTo: events)
        h.seekToEndOfFile(); h.write(Data("{\"type\":\"agent-state\"}\n".utf8)); try h.close()
    }

    let m = try pluginManifest(toml: ag.manifest, folder: "agents").get()
    let p = Process()
    p.executableURL = URL(filePath: "/bin/bash")
    p.arguments = [script.path]
    p.environment = pluginEnvironment(m, values: ["done_after": .int(0), "every": .int(1), "source": .string(source)]).merging(["TUIOS_BIN": fake.path]) { $1 }
    let out = Pipe(), inp = Pipe()
    p.standardOutput = out
    p.standardInput = inp
    try agents([("A", "working", false), ("B", "needs_input", true), ("C", "working", false)])
    try p.run()
    Thread.sleep(forTimeInterval: 1.5)
    try agents([("A", "needs_input", true), ("B", "needs_input", true), ("C", "working", false)])
    Thread.sleep(forTimeInterval: 1.5)
    try agents([("A", "needs_input", true), ("B", "needs_input", true), ("C", "done", false)])
    Thread.sleep(forTimeInterval: 1.5)
    try inp.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(5)
    while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    #expect(!p.isRunning)
    if p.isRunning { p.terminate() }
    // Nothing left behind: the subscribe (tail here) went with the plugin.
    Thread.sleep(forTimeInterval: 0.5)
    let left = Process()
    left.executableURL = URL(filePath: "/usr/bin/pgrep")
    left.arguments = ["-f", events.path]
    left.standardOutput = FileHandle.nullDevice
    try left.run(); left.waitUntilExit()
    #expect(left.terminationStatus == 1)

    let lines = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
    let notes = lines.compactMap { l -> GzymsNotification? in
        if case .notify(let n)? = pluginMessage(l, plugin: "agents", now: Date()) { return n } else { return nil }
    }
    // B already waited at the first look: no ping for it.
    #expect(notes.map(\.title) == ["A waits for you", "C is done"])
    #expect(notes.map(\.level) == [.warning, .info])
    #expect(notes.map(\.row) == ["A", "C"])  // each leaves the list with its agent
    let pills = lines.compactMap { l -> PluginItem? in
        if case .item(let i)? = pluginMessage(l, plugin: "agents", now: Date()) { return i } else { return nil }
    }
    #expect(pills.map(\.text) == ["1", "2", "2"])
    #expect(pills.last?.menu?.map(\.tag) == ["waits", "waits", "done"])
}

/// A click moves the client that shows a session (Gzyms is no pane, so tuios cannot pick one) and says in the log
/// what came of it: focused, failed with tuios's reason, or gone when the pane has closed.
@Test func agentsClickSaysFocusedFailedOrGone() throws {
    let ag = try #require(pluginCatalog.first { $0.name == "agents" })
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-agc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appending(path: "plugin.sh"), fake = dir.appending(path: "tuios"), calls = dir.appending(path: "calls")
    try ag.script.write(to: script, atomically: true, encoding: .utf8)
    let agents = #"{"agents":[{"window_id":"aaaaaaaa-1","session":"s1","state":"done","needs_you":false,"name":"A","message":""},"#
        + #"{"window_id":"bbbbbbbb-2","session":"bad","state":"done","needs_you":false,"name":"B","message":""}]}"#
    try """
    #!/bin/bash
    case "$1" in
      list-agents) echo '\(agents)';;
      list-clients) echo '[{"client_id":"cli","session":""},{"client_id":"c-other","session":"other"},{"client_id":"c-s1","session":"s1"}]';;
      switch-session) echo "$*" >> '\(calls.path)'; [ "$4" = bad ] && { echo "switch-session failed: no such session" >&2; exit 1; }; exit 0;;
      focus-window) echo "$*" >> '\(calls.path)';;
    esac
    """.write(to: fake, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    let m = try pluginManifest(toml: ag.manifest, folder: "agents").get()
    let p = Process()
    p.executableURL = URL(filePath: "/bin/bash")
    p.arguments = [script.path]
    p.environment = pluginEnvironment(m, values: ["source": .string("poll"), "every": .int(30), "terminal": .string("gzyms-test-no-such-app")])
        .merging(["TUIOS_BIN": fake.path]) { $1 }
    let out = Pipe(), inp = Pipe()
    p.standardOutput = out
    p.standardInput = inp
    try p.run()
    Thread.sleep(forTimeInterval: 1)  // the first look, so the plugin knows the agents
    for e in [#"{"event":"notify_open","id":"agent-aaaaaaaa-1-17"}"#, #"{"event":"click","id":"bbbbbbbb-2"}"#,
              #"{"event":"notify_open","id":"agent-cccccccc-3-4"}"#] {
        inp.fileHandleForWriting.write(Data((e + "\n").utf8))
    }
    try inp.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(10)
    while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning { p.terminate() }
    let logs = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").compactMap { l -> String? in
        if case .log(let s)? = pluginMessage(String(l), plugin: "agents", now: Date()) { return s } else { return nil }
    }
    #expect(logs == ["agents click: aaaaaaaa focused", "agents click: bbbbbbbb failed: switch-session failed: no such session",
                     "agents click: cccccccc gone"])
    // The client on the agent's own session moves. For another session, the first one that shows any.
    let made = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
    #expect(made == ["switch-session --client c-s1 s1", "focus-window -s s1 aaaaaaaa-1", "switch-session --client c-other bad"])
}

/// Runs the real script: a matching line becomes a notification of its level, the pill counts, EOF ends it all.
@Test func logWatcherNotifiesByRuleAndStopsWithStdin() throws {
    let lw = try #require(pluginCatalog.first { $0.name == "log-watcher" })
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-lw-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appending(path: "plugin.sh"), log = dir.appending(path: "app.log")
    try lw.script.write(to: script, atomically: true, encoding: .utf8)
    try Data().write(to: log)

    let m = try pluginManifest(toml: lw.manifest, folder: "log-watcher").get()
    let p = Process()
    p.executableURL = URL(filePath: "/bin/bash")
    p.arguments = [script.path]
    p.environment = pluginEnvironment(m, values: ["files": .strings([log.path]), "armageddon": .string("prod down"), "quiet": .int(30)])
    let out = Pipe(), inp = Pipe()
    p.standardOutput = out
    p.standardInput = inp
    try p.run()
    Thread.sleep(forTimeInterval: 1)  // tail starts at the end of the file
    let h = try FileHandle(forWritingTo: log)
    h.seekToEndOfFile()
    h.write(Data("all fine\nERROR db \"x\" timeout\nERROR again\nprod down now\nprod down still\n".utf8))
    try h.close()
    Thread.sleep(forTimeInterval: 2)
    inp.fileHandleForWriting.write(Data("{\"event\":\"open\",\"id\":\"logs\"}\n".utf8))
    try inp.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(5)
    while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    #expect(!p.isRunning)  // stdin closed: the watcher and its tail are gone
    if p.isRunning { p.terminate() }

    let lines = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
    let notes = lines.compactMap { l -> GzymsNotification? in
        if case .notify(let n)? = pluginMessage(l, plugin: "log-watcher", now: Date()) { return n } else { return nil }
    }
    // The second ERROR and the second armageddon fall in the quiet window: only counted.
    #expect(notes.map(\.level) == [.error, .armageddon])
    #expect(notes.first?.body == "ERROR db \"x\" timeout")
    let pills = lines.compactMap { l -> PluginItem? in
        if case .item(let i)? = pluginMessage(l, plugin: "log-watcher", now: Date()) { return i } else { return nil }
    }
    #expect(pills.map(\.text) == ["", "1", "2", "3", "4", ""])  // the list opened: seen
    #expect(pills[3].color == "mauve" && pills[3].menu?.first?.tag == "armageddon")
}

@Test func symbolsInAPluginsTextAreOnlyRealNames() {
    let known: (String) -> Bool = { ["xmark.circle", "clock"].contains($0) }
    #expect(textPieces(":xmark.circle: 2 :clock: 1", isSymbol: known) == [.symbol("xmark.circle"), .text(" 2 "), .symbol("clock"), .text(" 1")])
    #expect(textPieces("at 12:30:00", isSymbol: known) == [.text("at 12:30:00")])
    #expect(textPieces("a :nope: b :clock:", isSymbol: known) == [.text("a :nope: b "), .symbol("clock")])
    #expect(textPieces("", isSymbol: known) == [])
    #expect(textPieces(":xmark.circle@red: 2 :clock@#ff8800: 1 :nope@red:", isSymbol: known)
            == [.symbol("xmark.circle", color: "red"), .text(" 2 "), .symbol("clock", color: "#ff8800"), .text(" 1 :nope@red:")])
}

// MARK: - Catalog updates

private func catalogDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "gzyms-cat-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private let v1 = CatalogPlugin(name: "demo", summary: "", manifest: "name = \"Demo\"\ncommand = \"./plugin.sh\"\n", script: "echo v1\n")
private let v2 = CatalogPlugin(name: "demo", summary: "", manifest: v1.manifest, script: "echo v2\n")

private func script(_ d: URL) -> String { (try? String(contentsOf: d.appending(path: "demo/plugin.sh"), encoding: .utf8)) ?? "" }

@Test func untouchedCatalogCopyIsReplacedByTheNewVersion() throws {
    let d = try catalogDir(); defer { try? FileManager.default.removeItem(at: d) }
    try installCatalogPlugin(in: d, v1)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v1]) == .current)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v2]) == .updated)
    #expect(script(d) == v2.script)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v2]) == .current)
    #expect(try syncCatalogPlugin(in: d, folder: "other", catalog: [v2]) == .notCatalog)
}

@Test func editedCatalogCopyIsLeftAloneUntilReplacedByHand() throws {
    let d = try catalogDir(); defer { try? FileManager.default.removeItem(at: d) }
    try installCatalogPlugin(in: d, v1)
    try "echo mine\n".write(to: d.appending(path: "demo/plugin.sh"), atomically: true, encoding: .utf8)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v1]) == .edited)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v2]) == .editedCatalogNewer)
    #expect(script(d) == "echo mine\n")

    let bak = try replaceWithCatalog(in: d, folder: "demo", now: Date(timeIntervalSince1970: 0), catalog: [v2])
    #expect(isPluginBackup(bak.lastPathComponent))
    #expect((try? String(contentsOf: bak.appending(path: "plugin.sh"), encoding: .utf8)) == "echo mine\n")
    #expect(script(d) == v2.script)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v2]) == .current)
}

@Test func installWithoutMarkerIsAdoptedWhenSameAndKeptWhenDifferent() throws {
    let d = try catalogDir(); defer { try? FileManager.default.removeItem(at: d) }
    try installPlugin(in: d, folder: "demo", manifest: v2.manifest, script: v2.script)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v2]) == .current)
    #expect(FileManager.default.fileExists(atPath: d.appending(path: "demo/\(catalogMarker)").path))

    try FileManager.default.removeItem(at: d.appending(path: "demo"))
    try installPlugin(in: d, folder: "demo", manifest: v1.manifest, script: v1.script)
    #expect(try syncCatalogPlugin(in: d, folder: "demo", catalog: [v2]) == .editedCatalogNewer)
    #expect(script(d) == v1.script)
}

/// What the host starts is read after the swap: running the folder's script right then prints the new version.
@Test func startReadsTheFolderAfterTheSwap() throws {
    let d = try catalogDir(); defer { try? FileManager.default.removeItem(at: d) }
    try installCatalogPlugin(in: d, v1)
    let r = pluginTomlForStart(in: d, folder: "demo", catalog: [v2])
    #expect(try r.sync.get() == .updated)
    let m = try pluginManifest(toml: #require(r.toml), folder: "demo").get()
    let p = Process(), out = Pipe()
    p.executableURL = URL(filePath: "/bin/sh")
    p.arguments = ["-c", m.command]
    p.currentDirectoryURL = d.appending(path: "demo")
    p.standardOutput = out
    try p.run()
    p.waitUntilExit()
    #expect(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "v2\n")
}

// MARK: - Errors stay visible

/// Runs a plugin script, lets it print for `seconds`, closes stdin and returns what it printed as pills.
private func pills(of script: String, env: [String: String], seconds: Double = 2) throws -> [PluginItem] {
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-err-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "plugin.sh")
    try script.write(to: file, atomically: true, encoding: .utf8)
    let p = Process(), out = Pipe(), inp = Pipe()
    p.executableURL = URL(filePath: "/bin/bash")
    p.arguments = [file.path]
    p.environment = env
    p.standardOutput = out
    p.standardInput = inp
    try p.run()
    Thread.sleep(forTimeInterval: seconds)
    try inp.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(5)
    while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if p.isRunning { p.terminate() }
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").compactMap { l in
        if case .item(let i)? = pluginMessage(String(l), plugin: "t", now: Date()) { return i } else { return nil }
    }
}

/// No tuios, and a tuios that stops answering after the first look: the pill keeps its numbers and says it failed. It recovers by itself.
@Test func agentsSaysWhenTuiosIsMissingOrStopsAnswering() throws {
    let ag = try #require(pluginCatalog.first { $0.name == "agents" })
    let none = try pills(of: ag.script, env: ["TUIOS_BIN": "/nonexistent/tuios", "PATH": "/usr/bin:/bin"], seconds: 0.5)
    #expect(none.map(\.text) == ["no tuios"] && none.first?.error?.contains("tuios is not installed") == true)

    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-agf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let fake = dir.appending(path: "tuios"), down = dir.appending(path: "down")
    let one = #"{"agents":[{"window_id":"a","session":"s","state":"needs_input","needs_you":true,"name":"A","message":""}]}"#
    try "#!/bin/bash\n[ -e '\(down.path)' ] && exit 1\necho '\(one)'\n".write(to: fake, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    let m = try pluginManifest(toml: ag.manifest, folder: "agents").get()
    let env = pluginEnvironment(m, values: ["source": .string("poll"), "every": .int(1)]).merging(["TUIOS_BIN": fake.path, "PATH": "/usr/bin:/bin"]) { $1 }
    // The first look is fine, then tuios goes down.
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { try? "".write(to: down, atomically: true, encoding: .utf8) }
    let seen = try pills(of: ag.script, env: env, seconds: 3.5)
    #expect(seen.first?.text == "1" && seen.first?.error == nil)
    #expect(seen.last?.text == "1" && seen.last?.error?.contains("tuios did not answer") == true)
    #expect(seen.last?.menu?.first?.text == "A")
}

/// A file that exists and cannot be read would never match: the pill says so.
@Test func logWatcherSaysWhenAFileCannotBeRead() throws {
    let lw = try #require(pluginCatalog.first { $0.name == "log-watcher" })
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-lwe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dir.appending(path: "locked.log").path); try? FileManager.default.removeItem(at: dir) }
    let locked = dir.appending(path: "locked.log")
    try "x".write(to: locked, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    let m = try pluginManifest(toml: lw.manifest, folder: "log-watcher").get()
    let r = try pills(of: lw.script, env: pluginEnvironment(m, values: ["files": .strings([locked.path])]).merging(["PATH": "/usr/bin:/bin"]) { $1 }, seconds: 1)
    #expect(r.last?.error == "Cannot read \(locked.path). Check its permissions.")
}

@Test func theStarWatcherIsInTheCatalogWithItsOptions() throws {
    let c = try #require(pluginCatalog.first { $0.name == "star-watcher" })
    let m = try pluginManifest(toml: c.manifest, folder: c.name).get()
    #expect(m.options.map(\.key) == ["repos", "every"] && m.icon == "star")
    #expect(m.options.map(\.kind) == [.list, .number])
}
