import Foundation
import Testing
@testable import GzymsCore

private let at0 = Date(timeIntervalSince1970: 1000)

private func parsed(_ args: [String]) -> GzymsNotification? { try? parseNotify(args, now: at0).get() }
private func failure(_ args: [String]) -> String? {
    if case .failure(let e) = parseNotify(args, now: at0) { return e.message }
    return nil
}

@Test func titleIsRequired() {
    #expect(failure([])?.contains("--title") == true)
    #expect(failure(["--body", "x"])?.contains("--title") == true)
}

@Test func defaultsAreInfoAndFreshId() {
    let a = parsed(["--title", "hi"])
    let b = parsed(["--title", "hi"])
    #expect(a?.level == .info)
    #expect(a?.app == nil)
    #expect(a?.at == at0)
    #expect(a?.reminder == false)
    #expect(a?.id.isEmpty == false)
    #expect(a?.id != b?.id)
}

@Test func allFlagsParse() {
    let n = parsed(["--title", "Build", "--subtitle", "main", "--body", "green", "--level", "error", "--id", "ci-1",
                    "--app", "com.app", "--link", "https://a", "--alt-link", "gh pr view", "--sound", "success", "--screen", "built-in"])
    #expect(n == GzymsNotification(id: "ci-1", app: "com.app", level: .error, title: "Build", subtitle: "main", body: "green",
                                   link: "https://a", altLink: "gh pr view", sound: "success", at: at0, screen: "built-in"))
}

@Test func badLevelListsLevels() {
    #expect(failure(["--title", "x", "--level", "loud"])?.contains("info, warning, error, critical, armageddon") == true)
}

@Test func unknownFlagAndMissingValueFail() {
    #expect(failure(["--title", "x", "--colour", "red"])?.contains("--colour") == true)
    #expect(failure(["--title"])?.contains("--title") == true)
}

@Test func jsonRoundTrip() throws {
    let n = try #require(parsed(["--title", "zażółć", "--body", "a \"quoted\" line", "--level", "critical", "--app", "com.app"]))
    #expect(GzymsNotification(json: n.json) == n)
    #expect(GzymsNotification(json: "{not json") == nil)
}

@Test func soundVariantsMapToSystemSounds() {
    func n(_ level: NotifyLevel, _ sound: String?) -> GzymsNotification {
        GzymsNotification(id: "x", app: nil, level: level, title: "t", subtitle: nil, body: nil, link: nil, altLink: nil,
                          sound: sound, at: at0)
    }
    #expect(soundSource(for: n(.info, "success"), choices: [:]) == .system("Glass"))
    #expect(soundSource(for: n(.info, "fail"), choices: [:]) == .system("Basso"))
    #expect(soundSource(for: n(.info, "waiting"), choices: [:]) == .system("Submarine"))
    #expect(soundSource(for: n(.info, "message"), choices: [:]) == .system("Pop"))
    #expect(soundSource(for: n(.info, "Hero"), choices: [:]) == .system("Hero"))  // a macOS sound name passes through
    #expect(soundSource(for: n(.error, nil), choices: [:]) == .system("Basso"))   // spec: error comes with fail
    #expect(soundSource(for: n(.info, nil), choices: [:]) == .system("Pop"))  // no sound named: info sounds as message
}

@Test func notifyCompactNeedsAnAppAndNoTitle() {
    let n = parsed(["--compact", "--app", "com.apple.mail"])
    #expect(n?.compact == true && n?.title == "" && n?.app == "com.apple.mail")
    #expect(failure(["--compact"])?.contains("--app") == true)
    #expect(parsed(["--title", "x", "--reminder"])?.reminder == true)
}

@Test func setReadsKeysAndValuesLikeTheFile() {
    #expect(configKey("appearance.animations")! == (["appearance"], "animations"))
    #expect(configKey("notifications.apps.\"com.x.y\".banner")! == (["notifications", "apps", "com.x.y"], "banner"))
    #expect(configKey("theme")! == ([], "theme"))
    #expect(configKey("a..b") == nil)
    #expect(tomlValue(cli: "false") == .bool(false))
    #expect(tomlValue(cli: "0") == .int(0))
    #expect(tomlValue(cli: "1.5") == .double(1.5))
    #expect(tomlValue(cli: "[5, 0, -3]") == .ints([5, 0, -3]))
    #expect(tomlValue(cli: "[\"a b\", c]") == .strings(["a b", "c"]))
    #expect(tomlValue(cli: "mocha-neon") == .string("mocha-neon"))
}

@Test func shortFlagsParseLikeLongOnes() throws {
    let n = try parseNotify(["-t", "Hi", "-b", "there", "-l", "error", "-a", "com.x", "-i", "x1", "-s", "sub", "-r", "-c"], now: Date()).get()
    #expect(n.title == "Hi" && n.body == "there" && n.level == .error && n.app == "com.x" && n.id == "x1" && n.subtitle == "sub")
    #expect(n.reminder && n.compact)
    #expect(try parseNotify(["--title", "x", "--body", "-t"], now: Date()).get().body == "-t")  // a value stays a value
}
