import Foundation
import Testing
@testable import GzymsCore

private func store(after: Double = 300) -> NotificationStore {
    var s = NotificationStore()
    s.phone.url = "https://ntfy.sh/t"
    s.phone.after = after
    return s
}

@Test func aCriticalLeftAloneGoesToThePhoneAfterTheWait() {
    var s = store()
    s.post(note("a", level: .critical), now: 0)
    #expect(s.nextDeadline == 300)
    #expect(s.tick(now: 299).isEmpty)
    #expect(s.tick(now: 300).map(\.id) == ["a"])
    #expect(s.tick(now: 900).isEmpty)  // once
}

@Test func anyReactionKeepsItOffThePhone() {
    var s = store()
    s.post(note("a", level: .critical), now: 0)
    s.dismiss(now: 10)
    #expect(s.tick(now: 300).isEmpty)

    s.post(note("b", level: .critical), now: 0)
    s.snooze(minutes: 1, now: 5)
    #expect(s.tick(now: 30).isEmpty)

    s.post(note("c", level: .critical), now: 0)
    s.dismiss(now: 1)
    _ = s.open("c")  // from the list later
    #expect(s.tick(now: 1000).filter { $0.id == "c" }.isEmpty)
}

@Test func runningOutOnScreenIsNoReaction() {
    var s = store(after: 60)
    s.phone.levels = [.info]
    s.post(note("a"), now: 0)
    s.tick(now: 6)  // expired into the inbox
    #expect(s.banner == nil)
    #expect(s.tick(now: 60).map(\.id) == ["a"])
}

@Test func onlyChosenLevelsOrAppsGo() {
    var s = store(after: 0)
    s.post(note("info"), now: 0)
    #expect(s.tick(now: 0).isEmpty)
    s.appRules["com.slack"] = AppRule(phone: true)
    s.post(note("dm", app: "com.slack"), now: 0)
    #expect(s.tick(now: 0).map(\.id) == ["dm"])
    s.phone.url = nil
    s.post(note("x", level: .critical), now: 0)
    #expect(s.tick(now: 0).isEmpty)
}

@Test func anUpdateKeepsItsTimeAndSendsTheNewestText() {
    var s = store()
    s.post(note("a", "old", level: .critical), now: 0)
    s.post(note("a", "new", level: .critical), now: 200)
    #expect(s.tick(now: 300).map(\.title) == ["new"])
}

@Test func theRequestIsAnNtfyPost() throws {
    var p = PhonePush()
    p.url = "https://ntfy.sh/my-topic"
    var n = note("a", "Prod down", level: .critical)
    n.body = "5xx on all regions"
    n.link = "https://grafana.example/d/1"
    let r = try #require(p.request(n, appName: "Grafana"))
    #expect(r.httpMethod == "POST")
    #expect(String(decoding: r.httpBody ?? Data(), as: UTF8.self) == "5xx on all regions")
    let q = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(q.first { $0.name == "title" }?.value == "Grafana: Prod down")
    #expect(q.first { $0.name == "priority" }?.value == "5")
    #expect(q.first { $0.name == "click" }?.value == "https://grafana.example/d/1")
    p.url = "file:///etc/passwd"
    #expect(p.request(n, appName: nil) == nil)
}

@Test func phoneConfigIsRead() {
    let load = loadConfig(toml: """
    [notifications.phone]
    url = "https://ntfy.sh/my-topic"
    after = 2
    levels = ["error", "critical"]
    [notifications.apps."com.slack"]
    phone = true
    """)
    #expect(load.problems.isEmpty)
    #expect(load.config.phone.url == "https://ntfy.sh/my-topic")
    #expect(load.config.phone.after == 120)
    #expect(load.config.phone.levels == [.error, .critical])
    #expect(load.config.appRules["com.slack"]?.phone == true)
    let bad = loadConfig(toml: "[notifications.phone]\nurl = \"ntfy.sh/my-topic\"\nlevels = [\"loud\"]")
    #expect(bad.config.phone.url == nil)
    #expect(bad.problems.count == 2)
}

@Test func theJSONWebhookCarriesEveryField() throws {
    var p = PhonePush()
    p.url = "https://tina.example/hook"
    p.format = .json
    var n = note("a", "Prod down", app: "com.grafana", level: .critical)
    n.body = "5xx"
    let r = try #require(p.request(n, appName: "Grafana"))
    #expect(r.url?.absoluteString == "https://tina.example/hook")
    #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let o = try #require(try JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: String])
    #expect(o["title"] == "Prod down" && o["body"] == "5xx" && o["level"] == "critical" && o["app_name"] == "Grafana")
    #expect(o["subtitle"] == nil)
    #expect(loadConfig(toml: "[notifications.phone]\nformat = \"json\"").config.phone.format == .json)
}

@Test func pushoverNeedsBothKeysAndEscapesTheMessage() throws {
    var p = PhonePush()
    p.format = .pushover
    p.pushoverUser = "u1"
    #expect(!p.isOn)
    p.pushoverToken = "t1"
    let n = note("a", "a&b=c+d", level: .critical)
    let r = try #require(p.request(n, appName: nil))
    #expect(r.url?.absoluteString == PhonePush.pushoverAPI)
    let form = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
    #expect(form.contains("token=t1&user=u1&title=a%26b%3Dc%2Bd&message=a%26b%3Dc%2Bd&priority=1"))
    let c = loadConfig(toml: "[notifications.phone]\nformat = \"pushover\"\npushover_user = \"u\"\npushover_token = \"t\"").config.phone
    #expect(c.isOn && c.format == .pushover)
}

@Test func aPluginsNotesFollowItsOwnRule() {
    var s = NotificationStore()
    s.appRules["plugin:agents"] = AppRule(banner: false)
    s.post(note("plugin:agents:done-1", app: nil), now: 0)
    #expect(s.banner == nil)
    #expect(s.count(nil) == 1)
    #expect(ruleKey(note("plain", app: nil)) == nil)
    #expect(ruleKey(note("plugin:a:b:c", app: nil)) == "plugin:a")
}
