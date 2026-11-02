import Foundation

/// Shared by every source (CLI, plugins, macOS later): how long a banner stays and how loud it is.
public enum NotifyLevel: String, Codable, CaseIterable, Sendable {
    case info, warning, error, critical, armageddon

    /// Seconds on screen; nil = until acted on.
    public var seconds: Double? {
        switch self {
        case .info: 6
        case .warning: 8
        case .error: 12
        case .critical, .armageddon: nil
        }
    }

    public static let defaultSeconds = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.seconds) })
}

/// What the user set for one app in Settings (`[notifications.apps."<bundle id>"]`).
public struct AppRule: Equatable, Sendable {
    public var banner = true, sound = true, count = true
    public var level = AppLevel.normal
    /// Every notification of this app goes to the phone when left alone, whatever its level.
    public var phone = false
    public init(banner: Bool = true, sound: Bool = true, count: Bool = true, level: AppLevel = .normal, phone: Bool = false) {
        self.banner = banner; self.sound = sound; self.count = count; self.level = level; self.phone = phone
    }

    /// A rule only raises: an app set to critical still sends its own armageddon.
    public func raise(_ l: NotifyLevel) -> NotifyLevel {
        switch level {
        case .normal: l
        case .critical: l == .armageddon ? l : .critical
        case .armageddon: .armageddon
        }
    }
}

public enum AppLevel: String, Sendable { case normal, critical, armageddon }

/// The key of a notification's rule: its app's bundle id, or `plugin:<folder>` for a plugin's own.
public func ruleKey(_ n: GzymsNotification) -> String? {
    if let app = n.app { return app }
    let p = n.id.split(separator: ":", maxSplits: 2)
    return p.count == 3 && p[0] == "plugin" ? "plugin:\(p[1])" : nil
}

extension Dictionary where Key == String, Value == AppRule {
    public func rule(for n: GzymsNotification) -> AppRule { ruleKey(n).flatMap { self[$0] } ?? AppRule() }
}

/// Where the push goes: an ntfy topic (text as the body, title and priority as query parameters), any webhook
/// (one JSON object: Tina, n8n, Home Assistant), or Pushover (its own API, two keys).
public enum PushFormat: String, CaseIterable, Sendable { case ntfy, json, pushover }

/// `[notifications.phone]`: a banner nobody opened, dismissed or snoozed within `after` goes out as a POST.
/// Off until the address (or for Pushover both keys) is set.
public struct PhonePush: Equatable, Sendable {
    public var url: String?
    public var format = PushFormat.ntfy
    /// Pushover's user key and the API token of an application made at pushover.net.
    public var pushoverUser: String?, pushoverToken: String?
    /// Seconds without a reaction before it goes out; 0 = at once.
    public var after: Double = 300
    public var levels: Set<NotifyLevel> = [.critical, .armageddon]
    public init() {}

    public static let pushoverAPI = "https://api.pushover.net/1/messages.json"

    public var isOn: Bool { format == .pushover ? pushoverUser != nil && pushoverToken != nil : url != nil }

    public func wants(_ n: GzymsNotification, rule: AppRule) -> Bool {
        isOn && !n.compact && n.meetingStart == nil && (levels.contains(n.level) || rule.phone)
    }

    /// nil when it is off or the address is not http(s).
    public func request(_ n: GzymsNotification, appName: String?) -> URLRequest? {
        guard isOn, var c = URLComponents(string: format == .pushover ? Self.pushoverAPI : url ?? ""),
              ["http", "https"].contains(c.scheme?.lowercased()) else { return nil }
        let title = [appName, n.title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ": ")
        let text = [n.subtitle, n.body].compactMap { $0 }.joined(separator: "\n").nilIfEmpty ?? n.title
        let link = n.link.flatMap { $0.hasPrefix("http://") || $0.hasPrefix("https://") ? $0 : nil }
        let body: Data?
        var type: String?
        switch format {
        case .json:
            let fields: [String: String?] = ["id": n.id, "app": n.app, "app_name": appName, "level": n.level.rawValue, "title": n.title,
                                             "subtitle": n.subtitle, "body": n.body, "link": n.link,
                                             "at": ISO8601DateFormatter().string(from: n.at)]
            body = try? JSONSerialization.data(withJSONObject: fields.compactMapValues { $0 }, options: .sortedKeys)
            type = "application/json"
        case .pushover:
            // 1 = high: sounds even in the quiet hours. 2 would repeat until acknowledged on the phone.
            // A form, every value escaped whole: URLComponents would leave & = + in a message as they are.
            let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let fields = [("token", pushoverToken ?? ""), ("user", pushoverUser ?? ""), ("title", title), ("message", text),
                          ("priority", [.critical, .armageddon].contains(n.level) ? "1" : "0")] + (link.map { [("url", $0)] } ?? [])
            body = Data(fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: safe) ?? "")" }.joined(separator: "&").utf8)
            type = "application/x-www-form-urlencoded"
        case .ntfy:
            let priority = switch n.level { case .critical, .armageddon: "5"; case .error: "4"; default: "3" }
            c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "title", value: title), URLQueryItem(name: "priority", value: priority),
                                                   URLQueryItem(name: "tags", value: n.level.rawValue)]
                + (link.map { [URLQueryItem(name: "click", value: $0)] } ?? [])
            body = Data(text.utf8)
        }
        guard let to = c.url else { return nil }
        var r = URLRequest(url: to, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.httpBody = body
        if let type { r.setValue(type, forHTTPHeaderField: "Content-Type") }
        return r
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

public struct GzymsNotification: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// Bundle id of the app it belongs to; nil = the 🔔.
    public var app: String?
    public var level: NotifyLevel
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var link: String?
    /// The second action, e.g. a PR in the console instead of the browser.
    public var altLink: String?
    public var sound: String?
    public var at: Date
    /// Came back from a snooze: drawn as a reminder and kept until acted on.
    public var reminder = false
    /// The instant "app X sent something" from the log, before the text lands (~5 s): only the app's icon.
    /// Never filed into an inbox; its row replaces it, or it leaves quietly.
    public var compact = false
    /// Part of a screen's name ("built-in", "dell"); nil = the screen HyprMac has focus on.
    public var screen: String?
    /// A meeting reminder: when it starts (seconds since 1970). Never expires; the countdown runs to the start,
    /// then the subtitle counts the minutes late.
    public var meetingStart: Double?
    /// When it ends: after the start the bottom line fills red with how much of it has gone by.
    public var meetingEnd: Double?

    public init(id: String, app: String?, level: NotifyLevel, title: String, subtitle: String?, body: String?,
                link: String?, altLink: String?, sound: String?, at: Date, reminder: Bool = false, screen: String? = nil) {
        self.id = id; self.app = app; self.level = level; self.title = title; self.subtitle = subtitle; self.body = body
        self.link = link; self.altLink = altLink; self.sound = sound; self.at = at; self.reminder = reminder; self.screen = screen
    }
}

extension GzymsNotification {
    public static func pending(app: String, at: Date) -> GzymsNotification {
        // The sound comes with the icon, ~5 s before the text: macOS banners (and their sounds) are off for apps Gzyms shows.
        var n = GzymsNotification(id: "pending-\(app)", app: app, level: .info, title: "", subtitle: nil, body: nil,
                                  link: nil, altLink: nil, sound: "message", at: at)
        n.compact = true
        return n
    }

    /// Order in the stack: a meeting or a reminder never expires, so it ranks with critical.
    var rank: Int {
        switch level {
        case .armageddon: 4
        case _ where level == .critical || reminder || meetingStart != nil: 3
        case .error: 2
        case .warning: 1
        default: 0
        }
    }
}

/// One island with a stack (M3c): the banner on screen and up to three waiting under it, snoozed ones waiting to
/// come back, and an inbox per app (newest first). A higher level jumps in at once, the rest waits its turn.
public struct NotificationStore: Sendable {
    /// Waiting ones keep `left` (nil = the full time of their level), so only the banner on screen runs out.
    /// `heard`: its sound played already, so coming back into the stack stays quiet.
    private struct Entry: Sendable { var n: GzymsNotification; var seq: Int; var left: Double?; var heard = true }
    /// By rank, then arrival. Entries never move: next and previous move the cursor, so each keeps its place.
    private var stack: [Entry] = []
    /// No room in the stack: they wait in their list (so the count is right at once) and come up in order when room frees.
    /// Opened or cleared from the list meanwhile, they never come up.
    private var overflow: [Entry] = []
    /// What entered the stack (or a priority one that has to wait) since the app last asked: it plays their sounds.
    private var sounds: [GzymsNotification] = []
    /// `[notifications] priority`: these sound at once even while they wait outside the stack.
    public var priority = DNDBreak.priorityDefaults
    private var cursor = 0
    private var seq = 0
    public static let maxWaiting = 3
    private var deadline: Double?    // when the banner expires; nil = until acted on, or paused
    private var pausedLeft: Double?  // seconds left while the pointer is on the banner
    public private(set) var inboxes: [String?: [GzymsNotification]] = [:]
    private var snoozed: [(n: GzymsNotification, at: Double)] = []
    /// Apps whose pending icon was closed or opened: their next row is filed quietly, not shown (Greg).
    private var quiet: [String: Double] = [:]
    /// From the config: seconds on screen per level (nil = until acted on), and the per-app rules.
    public var levelSeconds = NotifyLevel.defaultSeconds
    public var appRules: [String: AppRule] = [:]
    public var phone = PhonePush()
    /// Shown or waiting and not acted on yet: when each goes to the phone. Opening, dismissing, snoozing or clearing takes it off.
    private var toPhone: [String: (n: GzymsNotification, at: Double)] = [:]
    /// Do Not Disturb until then (`.distantFuture` = until turned off), nil = off. Turned off by the app when its time comes.
    public private(set) var dnd: Date?
    /// `[dnd] breaks_through`: what still comes up on screen during Do Not Disturb.
    public var breaksThrough = DNDBreak.defaults

    public init() {}

    /// During Do Not Disturb everything else goes quietly to its list (and to the phone, as always).
    public func quiet(_ n: GzymsNotification) -> Bool {
        dnd != nil && !breaksThrough.covers(n)
    }

    /// The notifications to sound since the last call, each once.
    public mutating func takeSounds() -> [GzymsNotification] {
        defer { sounds = [] }
        return sounds
    }

    /// Turning it on files what is on screen and waiting; turning it off brings nothing back, the lists keep it.
    public mutating func setDND(_ until: Date?, now: Double) {
        dnd = until
        guard until != nil else { return }
        let shown = banner?.id
        let filed = stack.filter { quiet($0.n) }.map(\.seq)
        for e in stack where filed.contains(e.seq) { file(e.n) }
        stack.removeAll { filed.contains($0.seq) }
        overflow = overflow.filter { !quiet($0.n) }  // already in their lists
        refill(keep: shown, now: now)
    }

    public var banner: GzymsNotification? { stack.isEmpty ? nil : stack[cursor].n }
    public var waiting: Int { max(0, stack.count - 1) }
    public func contains(_ id: String) -> Bool { stack.contains { $0.n.id == id } }
    /// The waiting ones in the order next brings them up.
    public var queue: [GzymsNotification] {
        stack.isEmpty ? [] : (stack[(cursor + 1)...] + stack[..<cursor]).map(\.n)
    }
    /// The banner on screen and the waiting ones, in stack order.
    public var stacked: [GzymsNotification] { stack.map(\.n) }

    public func inbox(_ app: String?) -> [GzymsNotification] { inboxes[app] ?? [] }
    public func count(_ app: String?) -> Int { inboxes[app]?.count ?? 0 }

    public mutating func post(_ n: GzymsNotification, now: Double) {
        var n = n
        let rule = appRules.rule(for: n)
        n.level = rule.raise(n.level)
        // Banner off: straight into the count, unless it is loud enough that it must be seen.
        if !rule.banner, n.level != .critical, n.level != .armageddon, !contains(n.id) {
            if n.compact { return }
            if let i = inboxes[n.app]?.firstIndex(where: { $0.id == n.id }) { inboxes[n.app]?[i] = n } else { file(n); arm(n, now: now) }
            return
        }
        if !n.compact, let app = n.app, let until = quiet.removeValue(forKey: app), now < until { file(n); return }
        if banner?.id == n.id { stack[cursor].n = n; stack[cursor].left = nil; arm(n, now: now); start(now: now); return }
        if let i = stack.firstIndex(where: { $0.n.id == n.id }) { stack[i].n = n; arm(n, now: now); return }
        if let i = inboxes[n.app]?.firstIndex(where: { $0.id == n.id }) { inboxes[n.app]?[i] = n; return }
        if let i = snoozed.firstIndex(where: { $0.n.id == n.id }) { snoozed[i].n = n; return }
        insert(n, now: now)
    }

    /// Returns what is due for the phone now.
    @discardableResult public mutating func tick(now: Double) -> [GzymsNotification] {
        // A pending icon that waited in vain just leaves: its late row may still show. Running out is no reaction.
        if banner != nil, let d = deadline, now >= d { file(takeShown(now: now)) }
        snoozed.sort { $0.at < $1.at }
        while let first = snoozed.first, first.at <= now {
            snoozed.removeFirst()
            var n = first.n
            n.reminder = true
            insert(n, now: now)
        }
        let due = toPhone.filter { $0.value.at <= now }
        due.keys.forEach { toPhone[$0] = nil }
        return due.values.sorted { $0.at < $1.at }.map(\.n)
    }

    public mutating func hover(_ on: Bool, now: Double) {
        if on, let d = deadline { pausedLeft = max(0, d - now); deadline = nil }
        if !on, let left = pausedLeft { deadline = now + left; pausedLeft = nil }
    }

    /// Scroll down or the next letter; wraps around. Nothing moves under an armageddon: it waits for its click.
    public mutating func next(now: Double) { step(1, now: now) }
    public mutating func previous(now: Double) { step(-1, now: now) }

    public mutating func open(_ id: String, now: Double = 0) -> GzymsNotification? {
        toPhone[id] = nil
        if let b = banner, b.id == id { quietIfPending(b, now: now); return takeShown(now: now) }
        if let i = stack.firstIndex(where: { $0.n.id == id }) {
            let keep = banner?.id
            let e = stack.remove(at: i)
            refill(keep: keep, now: now)
            return e.n
        }
        for (app, list) in inboxes {
            if let i = list.firstIndex(where: { $0.id == id }) { return inboxes[app]?.remove(at: i) }
        }
        return nil
    }

    /// "Done, nothing to do with it" (Greg): gone for good. Only a banner left to expire, or pushed out of the
    /// stack, lands in its app's list.
    public mutating func dismiss(now: Double) {
        guard let b = banner else { return }
        toPhone[b.id] = nil
        quietIfPending(b, now: now)
        _ = takeShown(now: now)
    }

    public mutating func snooze(minutes: Int, now: Double) {
        guard let b = banner, !b.compact else { return }
        toPhone[b.id] = nil
        snoozed.append((takeShown(now: now), now + Double(minutes) * 60))
    }

    public mutating func remove(_ id: String, now: Double) { _ = open(id, now: now) }
    public mutating func clearAll(_ app: String?) {
        inboxes[app]?.forEach { toPhone[$0.id] = nil }
        inboxes[app] = nil
    }

    public var isPaused: Bool { pausedLeft != nil }

    public func remaining(now: Double) -> Double? { pausedLeft ?? deadline.map { max(0, $0 - now) } }

    /// The next moment `tick` has work: the banner's expiry, the earliest snooze coming back or a push falling due.
    public var nextDeadline: Double? { ([deadline] + snoozed.map(\.at) + toPhone.values.map(\.at)).compactMap { $0 }.min() }

    /// What survives a bar restart (notifications.json): the lists and the snoozes, in wall time since uptime starts
    /// over on a reboot. The stack is saved as list rows, so a crash loses nothing either, and `queued` keeps the
    /// stack and the ones waiting for it in line, so they come up again in that order.
    public struct Saved: Codable, Equatable, Sendable {
        public struct Snooze: Codable, Equatable, Sendable { public var n: GzymsNotification; public var at: Date }
        /// One row of `inbox` in line for the stack: whether it sounded already, and whether it came back from a snooze.
        public struct Queued: Codable, Equatable, Sendable { public var id: String; public var heard: Bool; public var reminder: Bool }
        public var inbox: [GzymsNotification]
        public var snoozed: [Snooze]
        public var dnd: Date?
        public var queued: [Queued]?
    }

    public func saved(now: Double, wall: Date) -> Saved {
        var copy = self
        // A meeting comes back from the calendar; a pending icon was never a row.
        let line = (stack.isEmpty ? [] : stack[cursor...] + stack[..<cursor]).filter { $0.n.meetingStart == nil && !$0.n.compact }
            + overflow.sorted(by: Self.order)
        for e in stack where e.n.meetingStart == nil { copy.file(e.n) }
        // Sorted by app: the same lists always give the same bytes, so an unchanged store is not written again.
        return Saved(inbox: copy.inboxes.sorted { ($0.key ?? "") < ($1.key ?? "") }.flatMap(\.value),
                     snoozed: snoozed.map { .init(n: $0.n, at: wall + ($0.at - now)) }, dnd: dnd,
                     queued: line.map { .init(id: $0.n.id, heard: $0.heard, reminder: $0.n.reminder) })
    }

    /// A snooze whose time passed while the bar was off comes back on the next tick. The ones in line come up in
    /// the same order, the first on screen with its full time.
    public mutating func restore(_ s: Saved, now: Double, wall: Date) {
        for n in s.inbox { inboxes[n.app, default: []].append(n) }
        snoozed = s.snoozed.map { ($0.n, now + max(0, $0.at.timeIntervalSince(wall))) }
        dnd = s.dnd.flatMap { $0 > wall ? $0 : nil }  // its time ran out while the bar was off
        for q in s.queued ?? [] {
            guard var n = s.inbox.first(where: { $0.id == q.id }), !quiet(n) else { continue }
            n.reminder = q.reminder
            seq += 1
            overflow.append(Entry(n: n, seq: seq, left: nil, heard: q.heard))
        }
        refill(keep: nil, now: now)
    }

    /// nil when there is none yet, or it does not decode: then it is moved aside, never lost.
    public static func load(_ url: URL, log: (String) -> Void) -> Saved? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(Saved.self, from: data) } catch {
            let aside = url.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            log("notifications: \(url.lastPathComponent) unreadable (\(error)), moved to \(aside.lastPathComponent), starting empty")
            return nil
        }
    }

    private mutating func insert(_ n: GzymsNotification, now: Double) {
        if quiet(n) { file(n); arm(n, now: now); return }  // a pending icon is not filed: it just never shows
        // A pending icon shows only on an empty stack, and a full banner takes its place without filing it.
        if n.compact { guard banner?.compact ?? true else { return }; stack = [] }
        let replacesIcon = !n.compact && banner?.compact == true && banner?.app == n.app
        if banner?.compact == true { stack = []; clearClock() }
        arm(n, now: now)
        let shown = banner
        let jumps = shown.map { n.rank > $0.rank } ?? true
        if jumps, shown != nil { stack[cursor].left = remaining(now: now) }
        seq += 1
        stack.append(Entry(n: n, seq: seq, left: nil))
        stack.sort(by: Self.order)
        let on = jumps ? n.id : shown!.id
        // Over the limit: the lowest level, the newest of them, waits in its list. Never the one on screen.
        while waiting > Self.maxWaiting, var out = stack.filter({ $0.n.id != on }).min(by: { ($0.n.rank, -$0.seq) < ($1.n.rank, -$1.seq) }) {
            stack.removeAll { $0.seq == out.seq }
            if out.seq == seq { out.heard = priority.covers(n) }
            file(out.n)
            overflow.append(out)
        }
        // A text replacing its own app's icon stays quiet: the icon already played the sound.
        if stack.contains(where: { $0.seq == seq }) ? !replacesIcon : priority.covers(n) { sounds.append(n) }
        cursor = stack.firstIndex { $0.n.id == on } ?? 0
        if jumps { start(now: now) }
    }

    private static func order(_ a: Entry, _ b: Entry) -> Bool { (a.n.rank, -a.seq) > (b.n.rank, -b.seq) }

    /// Room in the stack: the waiting ones come up in order, each with the newest version of its row.
    /// Keeps `keep` on screen when it is still in the stack, else the top one starts its clock.
    private mutating func refill(keep: String?, now: Double) {
        overflow.sort(by: Self.order)
        while stack.count <= Self.maxWaiting, !overflow.isEmpty {
            var e = overflow.removeFirst()
            guard let i = inboxes[e.n.app]?.firstIndex(where: { $0.id == e.n.id }) else { continue }  // opened or cleared from its list
            let reminder = e.n.reminder
            e.n = inboxes[e.n.app]!.remove(at: i)
            e.n.reminder = reminder
            if !e.heard { e.heard = true; sounds.append(e.n) }
            stack.append(e)
        }
        stack.sort(by: Self.order)
        if let i = stack.firstIndex(where: { $0.n.id == keep }) { cursor = i; return }
        cursor = 0
        clearClock()
        if !stack.isEmpty { start(now: now) }
    }

    private mutating func step(_ by: Int, now: Double) {
        guard stack.count > 1, banner?.level != .armageddon else { return }
        let paused = isPaused  // the pointer is on the banner while it scrolls: the next one stands still too
        stack[cursor].left = remaining(now: now)
        cursor = (cursor + by + stack.count) % stack.count
        start(now: now)
        if paused { hover(true, now: now) }
    }

    /// The banner on screen leaves the stack; the highest waiting one comes up with the time it had left.
    private mutating func takeShown(now: Double) -> GzymsNotification {
        let n = stack.remove(at: cursor).n
        refill(keep: nil, now: now)
        return n
    }

    private mutating func start(now: Double) {
        let e = stack[cursor]
        pausedLeft = nil
        // A pending icon waits up to 10 s for its row (rows come in batches, up to ~13 s for a burst).
        let full = e.n.compact ? 10 : (e.n.reminder || e.n.meetingStart != nil) ? nil : levelSeconds[e.n.level] ?? e.n.level.seconds
        deadline = (e.left ?? full).map { now + $0 }
    }

    private mutating func arm(_ n: GzymsNotification, now: Double) {
        guard phone.wants(n, rule: appRules.rule(for: n)) else { return }
        toPhone[n.id] = (n, toPhone[n.id]?.at ?? now + phone.after)  // an update keeps its time, with the newest text
    }

    private mutating func quietIfPending(_ b: GzymsNotification, now: Double) {
        if b.compact, let app = b.app { quiet[app] = now + 15 }
    }

    private mutating func clearClock() { deadline = nil; pausedLeft = nil }

    private mutating func file(_ n: GzymsNotification) {
        guard !n.compact else { return }
        var n = n
        n.reminder = false
        inboxes[n.app, default: []].insert(n, at: 0)
    }
}

/// What gets through Do Not Disturb (`[dnd] breaks_through`).
public enum DNDBreak: String, CaseIterable, Sendable {
    case armageddon, meetings, critical
    public static let defaults: Set<DNDBreak> = [.armageddon, .meetings]
    /// `[notifications] priority`: what sounds at once even while it waits for room in the stack (Greg: critical, armageddon).
    public static let priorityDefaults: Set<DNDBreak> = [.armageddon, .critical]
}

extension Set where Element == DNDBreak {
    public func covers(_ n: GzymsNotification) -> Bool {
        (n.level == .armageddon && contains(.armageddon)) || (n.meetingStart != nil && contains(.meetings))
            || (n.level == .critical && contains(.critical))
    }
}

/// "Until tomorrow" in the Do Not Disturb popup: the next 8:00.
public func dndUntilMorning(now: Date, calendar: Calendar = .current) -> Date {
    calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, second: 0), matchingPolicy: .nextTime) ?? now + 12 * 3600
}

/// `gzyms dnd on [minutes]|off` → what goes to the bar ("on", "on:30", "off"); nil = wrong arguments.
public func dndMessage(_ args: [String]) -> String? {
    switch args.count {
    case 1 where ["on", "off"].contains(args[0]): args[0]
    case 2 where args[0] == "on": Int(args[1]).flatMap { $0 > 0 ? "on:\($0)" : nil }
    default: nil
    }
}

/// The bar's side of `dndMessage`: nil = not one, .some(nil) = off.
public func dndUntil(_ message: String, now: Date) -> Date?? {
    if message == "off" { return .some(nil) }
    if message == "on" { return .some(.distantFuture) }
    guard message.hasPrefix("on:"), let m = Int(message.dropFirst(3)), m > 0 else { return nil }
    return .some(now + Double(m) * 60)
}

/// What the 🔔 holds: notifications with no app, and from apps with no icon on the bar (background processes).
public func bellInbox(_ inboxes: [String?: [GzymsNotification]], onBar: Set<String>) -> [GzymsNotification] {
    inboxes.filter { app, _ in app.map { !onBar.contains($0) } ?? true }.values.flatMap { $0 }.sorted { $0.at > $1.at }
}

public func badgeText(_ count: Int) -> String { count > 9 ? "9+" : "\(count)" }
