import Foundation
import Testing
@testable import GzymsCore

/// Runs a catalog plugin's real script against a fake gh that answers with `answers[i]` from the i-th step on,
/// then closes stdin and returns every line it printed. `events` go to stdin after the last answer.
private func runGH(_ name: String, values: [String: TOMLValue], answers: [String], gh: String? = nil, noGH: Bool = false,
                   events: [String] = []) throws -> (notes: [GzymsNotification], pills: [PluginItem], lines: [String]) {
    let c = try #require(pluginCatalog.first { $0.name == name })
    let dir = FileManager.default.temporaryDirectory.appending(path: "gzyms-gh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appending(path: "plugin.sh"), fake = dir.appending(path: "gh"), answer = dir.appending(path: "answer.json")
    try c.script.write(to: script, atomically: true, encoding: .utf8)
    try (gh ?? "#!/bin/bash\n[ \"$1\" = auth ] && exit 0\ncat '\(answer.path)'\n").write(to: fake, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    try (answers.first ?? "").write(to: answer, atomically: true, encoding: .utf8)

    let m = try pluginManifest(toml: c.manifest, folder: name).get()
    let p = Process()
    p.executableURL = URL(filePath: "/bin/bash")
    p.arguments = [script.path]
    p.environment = pluginEnvironment(m, values: values.merging(["every": .int(1)]) { a, _ in a })
        .merging(["GH_BIN": noGH ? dir.appending(path: "nope").path : fake.path, "PATH": "/usr/bin:/bin"]) { $1 }
    let out = Pipe(), inp = Pipe()
    p.standardOutput = out
    p.standardInput = inp
    try p.run()
    Thread.sleep(forTimeInterval: 1.5)
    for a in answers.dropFirst() {
        try a.write(to: answer, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 1.5)
    }
    for e in events { inp.fileHandleForWriting.write(Data((e + "\n").utf8)); Thread.sleep(forTimeInterval: 0.5) }
    try inp.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(5)
    while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    #expect(!p.isRunning)  // stdin closed: the plugin and its clock are gone
    if p.isRunning { p.terminate() }

    let lines = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
    let notes = lines.compactMap { l -> GzymsNotification? in
        if case .notify(let n)? = pluginMessage(l, plugin: name, now: Date()) { return n } else { return nil }
    }
    let pills = lines.compactMap { l -> PluginItem? in
        if case .item(let i)? = pluginMessage(l, plugin: name, now: Date()) { return i } else { return nil }
    }
    return (notes, pills, lines)
}

private func check(_ name: String, _ conclusion: String?, status: String = "COMPLETED", url: String = "") -> String {
    let c = conclusion.map { "\"\($0)\"" } ?? "null"
    return "{\"__typename\":\"CheckRun\",\"name\":\"\(name)\",\"status\":\"\(status)\",\"conclusion\":\(c),\"detailsUrl\":\"\(url)\"}"
}

private func pr(_ n: Int, repo: String = "o/r", draft: Bool = false, mergeable: String = "MERGEABLE", review: String? = nil,
                perm: String = "WRITE", approvers: [String] = [], threads: [(resolved: Bool, last: String, bot: Bool)] = [],
                conv: [(at: String, by: String)] = [], checks: [String]? = []) -> String {
    let reviews = approvers.map { "{\"state\":\"APPROVED\",\"author\":{\"login\":\"\($0)\"}}" }.joined(separator: ",")
    let th = threads.map { "{\"isResolved\":\($0.resolved),\"comments\":{\"nodes\":[{\"author\":{\"login\":\"\($0.last)\",\"__typename\":\"\($0.bot ? "Bot" : "User")\"}}]}}" }
        .joined(separator: ",")
    let cv = conv.map { "{\"createdAt\":\"\($0.at)\",\"author\":{\"login\":\"\($0.by)\",\"__typename\":\"User\"}}" }.joined(separator: ",")
    let roll = checks.map { "{\"contexts\":{\"nodes\":[\($0.joined(separator: ","))]}}" } ?? "null"
    return """
    {"number":\(n),"title":"PR \(n)","url":"https://github.com/\(repo)/pull/\(n)","isDraft":\(draft),"mergeable":"\(mergeable)",
     "reviewDecision":\(review.map { "\"\($0)\"" } ?? "null"),"headRefName":"b\(n)","repository":{"nameWithOwner":"\(repo)","viewerPermission":"\(perm)"},
     "latestReviews":{"nodes":[\(reviews)]},"reviewThreads":{"nodes":[\(th)]},"comments":{"nodes":[\(cv)]},
     "commits":{"nodes":[{"commit":{"statusCheckRollup":\(roll)}}]}}
    """
}

private func search(_ prs: [String], extra: String = "") -> String {
    "{\"data\":{\"viewer\":{\"login\":\"me\"},\"search\":{\"nodes\":[\(prs.joined(separator: ","))]}\(extra)}}"
}

// The glyphs as the plugins print them: name, then the colour.
private let fixG = ":xmark.circle@red:", mergeG = ":checkmark.circle@green:", commentsG = ":bubble.left@sky:", draftG = ":square.and.pencil@mauve:"
private let failedG = ":xmark.circle@red:", runningG = ":arrow.triangle.2.circlepath@gold:", passedG = ":checkmark.circle@green:"

@Test func ghPRsClassifiesAndNotifiesWhatIsNew() throws {
    let first = search([
        pr(1, checks: [check("build", "FAILURE")]),
        pr(2, review: "APPROVED"),
        pr(3, review: "REVIEW_REQUIRED"),
        pr(4, threads: [(false, "me", false)]),          // MERGE but a conversation is open → resolve
        pr(5, perm: "READ"),                               // mergeable, but not ours to merge
        pr(6, draft: true),
        pr(7, threads: [(false, "dependabot", true)], conv: [("2026-11-01T10:00:00Z", "bob"), ("2026-11-01T11:00:00Z", "me")]),
    ])
    let second = search([
        pr(1, checks: [check("build", "FAILURE")]),
        pr(2, review: "APPROVED"),
        pr(3, review: "REVIEW_REQUIRED", approvers: ["bob"], threads: [(false, "alice", false)]),
        pr(4, threads: [(false, "me", false)]),
        pr(5, perm: "READ"),
        pr(6, draft: true),
        pr(7, threads: [(false, "dependabot", true)], conv: [("2026-11-01T10:00:00Z", "bob"), ("2026-11-01T11:00:00Z", "me")]),
    ])
    let r = try runGH("gh-prs", values: [:], answers: [first, second], events: ["{\"event\":\"open\",\"id\":\"prs\"}"])
    // The first answer is the baseline: no notes. Then PR 3 gets an approval (wins over its new comment).
    #expect(r.notes.map(\.title) == ["r#3 approved by bob"])
    #expect(r.notes.first?.link == "https://github.com/o/r/pull/3")
    #expect(r.pills.first?.text == "…")
    #expect(r.pills.contains { $0.text == "\(fixG) 1 \(mergeG) 1 \(draftG) 1" })
    let last = try #require(r.pills.last)
    #expect(last.text == "\(fixG) 1 \(mergeG) 1 \(commentsG) 1 \(draftG) 1")
    #expect(last.tooltip == "fix 1, merge 1, comments 1, draft 1")
    // Events, then what needs you (newest first), then the rest. PR 7's open bot thread still blocks the merge.
    #expect((last.menu ?? []).compactMap(\.tag) == [":hand.thumbsup: review", ":checkmark.bubble: resolve", ":checkmark.bubble: resolve", ":checkmark.circle: merge", ":xmark.circle: fix",
                                                           ":square.and.pencil: draft", ":lock.circle: blocked", ":hourglass: review?"])
}

/// The one pill and list a single answer ends in.
private func last(_ name: String, _ answer: String, values: [String: TOMLValue] = [:]) throws -> PluginItem {
    try #require(try runGH(name, values: values, answers: [answer]).pills.last)
}

@Test func ghPRsCountsAPRInEveryStateItIsIn() throws {
    // Three open threads from others are one PR with comments. It fails too, so it is counted in both.
    let both = pr(1, threads: [(false, "bob", false), (false, "bob", false), (false, "alice", false)], checks: [check("build", "FAILURE")])
    let it = try last("gh-prs", search([both, pr(2, review: "APPROVED", conv: [("2026-11-01T10:00:00Z", "bob")])]))
    #expect(it.text == "\(fixG) 1 \(mergeG) 1 \(commentsG) 2")
    let rows = try #require(it.menu).filter { $0.id != nil }
    #expect(rows.map(\.tag) == [":checkmark.circle: merge", ":xmark.circle: fix"])
    #expect(rows.map(\.detail) == [":circle.dashed: no CI  \(commentsG) comments", ":xmark.circle@red: failed  \(commentsG) comments"])
}

@Test func ghPRsCountsADraftOnlyAsADraft() throws {
    // A failing draft with comments raises neither the fix nor the comments glyph, but its row still says so, and what its CI did.
    let draft = pr(1, draft: true, threads: [(false, "bob", false)], checks: [check("build", "FAILURE")])
    let it = try last("gh-prs", search([draft, pr(2, review: "REVIEW_REQUIRED")]))
    #expect(it.text == "\(draftG) 1")
    #expect(it.tooltip == "draft 1")
    let row = try #require(it.menu?.first { $0.id == "pr:o/r#1" })
    #expect(row.tag == ":square.and.pencil: draft" && row.detail == ":xmark.circle@red: failed  \(commentsG) comments")
    #expect(try #require(it.menu?.first { $0.id == "pr:o/r#2" }).tag == ":hourglass: review?")
}

@Test func ghBuildsCountsARunOnceByItsState() throws {
    func target(_ n: Int, _ checks: [String]) -> String {
        "{\"number\":\(n),\"title\":\"PR \(n)\",\"url\":\"https://github.com/o/r/pull/\(n)\",\"repository\":{\"nameWithOwner\":\"o/r\"},\"commits\":{\"nodes\":[{\"commit\":{\"statusCheckRollup\":{\"contexts\":{\"nodes\":[\(checks.joined(separator: ","))]}}}}]}}"
    }
    let run = check("e2e", nil, status: "IN_PROGRESS"), fail = check("unit", "FAILURE")
    // PR 1 fails and still runs another check: it is failed, once. PR 2 only runs.
    let answer = "{\"data\":{\"search\":{\"nodes\":[\(target(1, [fail, run])),\(target(2, [run])),\(target(3, [check("unit", "SUCCESS")]))]}}}"
    let it = try last("gh-builds", answer)
    #expect(it.text == "\(failedG) 1 \(runningG) 1 \(passedG) 1")
    #expect(it.tooltip == "1 failed, 1 running, 1 passed")
    let tags = (it.menu ?? []).compactMap(\.tag)
    #expect(tags == [":xmark.circle: failed", ":arrow.triangle.2.circlepath: running", ":checkmark.circle: passed"])
}

@Test func ghPRsSaysWhatIsMissing() throws {
    let none = try runGH("gh-prs", values: [:], answers: [], noGH: true)
    #expect(none.pills.map(\.text) == ["install gh"])
    let logout = "#!/bin/bash\n[ \"$1\" = auth ] && exit 1\necho 'To get started with GitHub CLI, please run:  gh auth login' >&2\nexit 4\n"
    let r = try runGH("gh-prs", values: [:], answers: [""], gh: logout)
    #expect(r.pills.last?.text == "gh auth login")
    #expect(r.pills.last?.menu?.first?.text.contains("gh auth login") == true)
}

@Test func ghBuildsNotifiesWhenARunEnds() throws {
    func answer(pr: [String], main: [String]) -> String {
        let b = ",\"b0\":{\"object\":{\"url\":\"https://github.com/o/r/commit/abc\",\"statusCheckRollup\":{\"contexts\":{\"nodes\":[\(main.joined(separator: ","))]}}}}"
        return "{\"data\":{\"search\":{\"nodes\":[{\"number\":9,\"title\":\"PR 9\",\"url\":\"https://github.com/o/r/pull/9\",\"repository\":{\"nameWithOwner\":\"o/r\"},\"commits\":{\"nodes\":[{\"commit\":{\"statusCheckRollup\":{\"contexts\":{\"nodes\":[\(pr.joined(separator: ","))]}}}}]}}]}\(b)}}"
    }
    let r = try runGH("gh-builds", values: ["branches": .strings(["o/r@main", "not a branch"])], answers: [
        answer(pr: [check("test", nil, status: "IN_PROGRESS")], main: [check("deploy", nil, status: "IN_PROGRESS")]),
        answer(pr: [check("test", "FAILURE", url: "https://github.com/o/r/actions/runs/1/job/2")], main: [check("deploy", "SUCCESS")]),
    ])
    // notify = finished: the fail and the green end, no "started".
    #expect(r.notes.map(\.title).sorted() == ["r#9 CI failed: test", "r@main CI green"])
    let fail = try #require(r.notes.first { $0.title.hasPrefix("r#9") })
    #expect(fail.level == .warning && fail.link == "https://github.com/o/r/actions/runs/1/job/2")
    #expect(r.pills.contains { $0.text == "\(runningG) 2" })
    let last = try #require(r.pills.last)
    #expect(last.text == "\(failedG) 1 \(passedG) 1" && last.color == "red")
    #expect(last.menu?.first?.text == "Skipped, not owner/repo@branch: not a branch")
}

// MARK: every combination, through the plugins' jq programs

/// The jq program of a catalog plugin, run on one GitHub answer in "poll" mode with an empty state. Returns the pill it ends in.
private func pill(_ name: String, _ answer: String, branches: [(repo: String, ref: String)] = []) throws -> PluginItem {
    let c = try #require(pluginCatalog.first { $0.name == name })
    let a = try #require(c.script.range(of: "read -r -d '' PROG <<'JQ'\n"))
    let b = try #require(c.script.range(of: "\nJQ\n", range: a.upperBound..<c.script.endIndex))
    let prog = String(c.script[a.upperBound..<b.lowerBound])
    let br = "[" + branches.enumerated().map { "{\"i\":\($0.offset),\"repo\":\"\($0.element.repo)\",\"ref\":\"\($0.element.ref)\"}" }.joined(separator: ",") + "]"
    var args = ["-c", "--arg", "mode", "poll", "--arg", "err", "", "--arg", "errpill", "", "--argjson", "st", "{}", "--argjson", "snd", "{}"]
    if name == "gh-builds" { args += ["--argjson", "br", br, "--argjson", "bad", "[]"] }
    let p = Process(), inp = Pipe(), out = Pipe()
    p.executableURL = URL(filePath: "/usr/bin/jq")
    p.arguments = args + [prog]
    p.environment = [:]
    p.standardInput = inp
    p.standardOutput = out
    try p.run()
    inp.fileHandleForWriting.write(Data(answer.utf8))
    try inp.fileHandleForWriting.close()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    #expect(p.terminationStatus == 0)
    let items = text.split(separator: "\n").compactMap { l -> PluginItem? in
        if case .item(let i)? = pluginMessage(String(l), plugin: name, now: Date()) { return i } else { return nil }
    }
    return try #require(items.last)
}

private enum CI: String, CaseIterable, Sendable { case passed, running, failed, none, expected }
private enum Decision: String, CaseIterable, Sendable { case approved, required, changes, none }

/// One PR of the table: draft or not, its CI, a conflict, the review decision, a comment waiting for me.
private struct PRCase: Sendable, CustomTestStringConvertible {
    var draft: Bool, ci: CI, conflict: Bool, decision: Decision, comments: Bool
    var testDescription: String { "draft=\(draft) ci=\(ci) conflict=\(conflict) review=\(decision) comments=\(comments)" }
    static let all: [PRCase] = [false, true].flatMap { d in CI.allCases.flatMap { ci in [false, true].flatMap { cf in
        Decision.allCases.flatMap { dec in [false, true].map { cm in PRCase(draft: d, ci: ci, conflict: cf, decision: dec, comments: cm) } } } } }

    var json: String {
        let checks: [String]
        switch ci {
        case .passed: checks = [check("build", "SUCCESS")]
        case .running: checks = [check("build", nil, status: "IN_PROGRESS")]
        case .failed: checks = [check("build", "FAILURE")]
        case .none: checks = []
        case .expected: checks = ["{\"__typename\":\"StatusContext\",\"context\":\"e2e-required\",\"state\":\"EXPECTED\",\"targetUrl\":\"\"}"]
        }
        let review: String? = [.approved: "APPROVED", .required: "REVIEW_REQUIRED", .changes: "CHANGES_REQUESTED", .none: nil][decision]!
        return pr(1, draft: draft, mergeable: conflict ? "CONFLICTING" : "MERGEABLE", review: review,
                  conv: comments ? [("2026-11-01T10:00:00Z", "bob")] : [], checks: checks)
    }

    /// What the plugin has to print, worked out here from the rules and not from its code.
    var expected: (pill: String, color: String, tooltip: String, tag: String, tagColor: String, detail: String) {
        let pending = ci == .running || ci == .expected
        let e2e = ci == .expected && decision != .required   // a status waits and nothing like e2e runs: someone starts it
        let changes = decision == .changes
        let fix = ci == .failed || conflict || changes || e2e
        let merge = !draft && !fix && decision != .required && !pending
        var states: [(String, String)] = []  // glyph, word
        if draft { states = [(draftG, "draft")] } else {
            if fix { states.append((fixG, "fix")) }
            if merge { states.append((mergeG, "merge")) }
            if comments { states.append((commentsG, "comments")) }
        }
        let tag: (String, String) = draft ? (":square.and.pencil: draft", "mauve") : fix ? (":xmark.circle: fix", "red")
            : decision == .required ? (":hourglass: review?", "gold") : pending ? (":arrow.triangle.2.circlepath: CI runs", "gold") : (":checkmark.circle: merge", "green")
        let ciItem = [CI.passed: ":checkmark.circle@green: passed", .running: ":arrow.triangle.2.circlepath@gold: running", .failed: ":xmark.circle@red: failed",
                      .none: ":circle.dashed: no CI", .expected: ":arrow.triangle.2.circlepath@gold: running"][ci]!
        let detail = [ciItem] + (conflict ? [":exclamationmark.triangle@red: conflict"] : []) + (changes ? [":exclamationmark.circle@peach: changes requested"] : [])
            + (e2e ? [":play.circle@peach: run e2e"] : []) + (comments ? [commentsG + " comments"] : [])
        let color = states.contains { $0.1 == "fix" } ? "red" : states.contains { $0.1 == "comments" } ? "sky" : states.contains { $0.1 == "merge" } ? "green" : "overlay"
        return (states.map { "\($0.0) 1" }.joined(separator: " "), color, states.isEmpty ? "1 open pull requests" : states.map { "\($0.1) 1" }.joined(separator: ", "),
                tag.0, tag.1, detail.joined(separator: "  "))
    }
}

@Test("gh-prs: pill and row for every state a PR can be in", arguments: PRCase.all)
private func ghPRsEveryCombination(c: PRCase) throws {
    let it = try pill("gh-prs", search([c.json]))
    let e = c.expected
    #expect(it.text == e.pill)
    #expect(it.color == e.color)
    #expect(it.tooltip == e.tooltip)
    let row = try #require(it.menu?.first { $0.id == "pr:o/r#1" })
    #expect(row.tag == e.tag)
    #expect(row.color == e.tagColor)
    #expect(row.detail == e.detail)
}

/// One target of the builds table: its checks, a PR or a branch.
private struct BuildCase: Sendable, CustomTestStringConvertible {
    var failed: Bool, running: Bool, success: Bool, cancelled: Bool, branch: Bool
    var testDescription: String { "\(branch ? "branch" : "pr") failed=\(failed) running=\(running) success=\(success) cancelled=\(cancelled)" }
    static let all: [BuildCase] = [false, true].flatMap { br in (0..<16).map { n in
        BuildCase(failed: n & 1 != 0, running: n & 2 != 0, success: n & 4 != 0, cancelled: n & 8 != 0, branch: br) } }
    var checks: [String] {
        (failed ? [check("unit", "FAILURE")] : []) + (running ? [check("e2e", nil, status: "IN_PROGRESS")] : [])
            + (success ? [check("lint", "SUCCESS")] : []) + (cancelled ? [check("docs", "CANCELLED")] : [])
    }
    /// The state of the target by its worst check: failed, running, passed (all clean), done (ended, not clean), none (no checks).
    var state: String { failed ? "failed" : running ? "running" : checks.isEmpty ? "none" : cancelled ? "done" : "passed" }
}

private let buildTags = ["failed": ":xmark.circle: failed", "running": ":arrow.triangle.2.circlepath: running", "passed": ":checkmark.circle: passed",
                         "done": ":minus.circle: done", "none": ":circle.dashed: no CI"]
private let buildColors = ["failed": "red", "running": "gold", "passed": "green", "done": "overlay", "none": "overlay"]

private func buildsAnswer(prs: [[String]], branches: [[String]]) -> String {
    func roll(_ c: [String]) -> String { "{\"contexts\":{\"nodes\":[\(c.joined(separator: ","))]}}" }
    let nodes = prs.enumerated().map { n, c in
        "{\"number\":\(n + 1),\"title\":\"PR \(n + 1)\",\"url\":\"https://github.com/o/r/pull/\(n + 1)\",\"repository\":{\"nameWithOwner\":\"o/r\"},\"commits\":{\"nodes\":[{\"commit\":{\"statusCheckRollup\":\(roll(c))}}]}}"
    }.joined(separator: ",")
    let bs = branches.enumerated().map { n, c in ",\"b\(n)\":{\"object\":{\"url\":\"https://github.com/o/r/commit/\(n)\",\"statusCheckRollup\":\(roll(c))}}" }.joined()
    return "{\"data\":{\"search\":{\"nodes\":[\(nodes)]}\(bs)}}"
}

/// The pill the counts of these states make: failed, running, passed, each once per target.
private func buildsPill(_ states: [String]) -> (text: String, color: String, tooltip: String) {
    func n(_ s: String) -> Int { states.filter { $0 == s }.count }
    let parts = [(failedG, n("failed")), (runningG, n("running")), (passedG, n("passed"))].filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
    let color = n("failed") > 0 ? "red" : n("running") > 0 ? "gold" : n("passed") > 0 ? "green" : "overlay"
    return (parts.joined(separator: " "), color, "\(n("failed")) failed, \(n("running")) running, \(n("passed")) passed")
}

@Test("gh-builds: pill and row for every mix of checks of one target", arguments: BuildCase.all)
private func ghBuildsEveryCombination(c: BuildCase) throws {
    let it = c.branch ? try pill("gh-builds", buildsAnswer(prs: [], branches: [c.checks]), branches: [("o/r", "main")])
        : try pill("gh-builds", buildsAnswer(prs: [c.checks], branches: []))
    let e = buildsPill([c.state])
    #expect(it.text == e.text && it.color == e.color && it.tooltip == e.tooltip)
    let row = try #require(it.menu?.first { $0.id == (c.branch ? "t:o/r@main" : "t:o/r#1") })
    #expect(row.tag == buildTags[c.state] && row.color == buildColors[c.state])
    #expect(row.detail == (c.failed ? "unit" : ""))
}

@Test("gh-builds: several targets are counted once each, by their own state", arguments: [
    ["failed", "running", "passed"], ["failed", "failed", "running", "running", "passed"], ["passed", "passed", "passed"],
    ["running", "running"], ["none", "done", "passed"], ["failed", "none"], [],
])
private func ghBuildsMixes(states: [String]) throws {
    let checks = ["failed": [check("unit", "FAILURE"), check("e2e", nil, status: "IN_PROGRESS")], "running": [check("e2e", nil, status: "IN_PROGRESS")],
                  "passed": [check("lint", "SUCCESS")], "done": [check("docs", "CANCELLED")], "none": []]
    let it = try pill("gh-builds", buildsAnswer(prs: states.map { checks[$0]! }, branches: []))
    let e = buildsPill(states)
    #expect(it.text == e.text && it.color == e.color && it.tooltip == e.tooltip)
    // the list has one row per target, in the order failed, running, passed, done, none
    let tags = (it.menu ?? []).filter { $0.id != nil }.compactMap(\.tag)
    #expect(tags == ["failed", "running", "passed", "done", "none"].flatMap { s in states.filter { $0 == s }.map { _ in buildTags[s]! } })
}
