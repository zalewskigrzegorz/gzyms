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
    #expect(r.pills.contains { $0.text == ":xmark.circle: 1 :checkmark.circle: 1" })
    let last = try #require(r.pills.last)
    #expect(last.text == ":xmark.circle: 1 :checkmark.circle: 1 :bubble.left: 1")
    // Events, then what needs you (newest first), then the rest. PR 7's open bot thread still blocks the merge.
    #expect((last.menu ?? []).compactMap(\.tag) == [":hand.thumbsup: review", "resolve", "resolve", "merge ✓", "fix CI", "draft", "blocked", "review?"])
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
    #expect(r.pills.contains { $0.text == ":clock: 2" })
    let last = try #require(r.pills.last)
    #expect(last.text == ":xmark.circle: 1" && last.color == "red")
    #expect(last.menu?.first?.text == "Skipped, not owner/repo@branch: not a branch")
}
