import Foundation
import GzymsCore
import SQLite3

/// Notifications from other apps, read from macOS's Notification Center database (spike S1). Each row lands
/// ~5 s after delivery; watching `db-wal` catches it without polling. Needs Full Disk Access.
/// Everything runs on its own queue, so a slow read never shows up as bar lag.
final class NotificationCenterSource: @unchecked Sendable {
    private let path = FileManager.default.homeDirectoryForCurrentUser.path
        + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    private let queue = DispatchQueue(label: "dev.gzyms.nc")
    private let deliver: @MainActor ([GzymsNotification]) -> Void
    private var db: OpaquePointer?
    /// New rows are told apart by delivery time and uuid; row numbers come back after an app removes its rows.
    private var lastDelivered: Double = 0
    private var seen: [String: Double] = [:]  // uuid → delivered, for rows at or near `lastDelivered`
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var retry: DispatchSourceTimer?
    private var poll: DispatchSourceTimer?
    private var warned = false

    init(deliver: @escaping @MainActor ([GzymsNotification]) -> Void) { self.deliver = deliver }

    /// Full Disk Access. A running process keeps reading files after the switch goes off, so the switch itself is
    /// read from macOS's own grant table (readable only with that access); without it, a read of the database decides.
    nonisolated static func hasAccess() -> Bool {
        let (allowed, how) = tccSwitch()
        if how != lastHow { lastHow = how; log("permissions: full disk access check: \(how)") }
        return allowed ?? canReadDatabase()
    }

    /// nil = the table could not be read or holds no row for Gzyms; `how` says which, for the log.
    private nonisolated static func tccSwitch() -> (Bool?, String) {
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        let path = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard sqlite3_open_v2("file:\(path)?mode=ro", &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return (nil, "tcc open failed") }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = "select auth_value, client from access where service = 'kTCCServiceSystemPolicyAllFiles' and client like ?"
        guard sqlite3_prepare_v2(handle, sql, -1, &st, nil) == SQLITE_OK else {
            return (nil, "tcc query failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        // By bundle id, or by path when the app was added from Finder as a file.
        sqlite3_bind_text(st, 1, "%gzyms%", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var rows: [String] = []
        var allowed: Bool?
        while sqlite3_step(st) == SQLITE_ROW {
            let value = sqlite3_column_int(st, 0)
            let client = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? "?"
            rows.append("\(client)=\(value)")
            if client == Bundle.main.bundleIdentifier || client.hasSuffix("/Gzyms.app") { allowed = (allowed ?? false) || value == 2 }
        }
        return (allowed, rows.isEmpty ? "tcc no row" : "tcc " + rows.joined(separator: " "))
    }

    nonisolated(unsafe) private static var lastHow = ""  // main thread only

    private nonisolated static func canReadDatabase() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        guard sqlite3_open_v2("file:\(path)?mode=ro", &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return false }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        return sqlite3_prepare_v2(handle, "select count(*) from app", -1, &st, nil) == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW
    }

    func start() { queue.async { self.open() } }

    /// Without Full Disk Access the open fails; try again every 10 s so a grant works without a restart.
    private func open() {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2("file:\(path)?mode=ro", &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        // The open can succeed lazily; the first read is what tells whether access was granted.
        if rc != SQLITE_OK || latest(handle) == nil {
            sqlite3_close(handle)
            if !warned { log("nc: needs Full Disk Access (macOS notifications from other apps are off until then)"); warned = true }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 10)
            t.setEventHandler { [weak self] in self?.retry = nil; self?.open() }
            t.resume()
            retry = t
            return
        }
        db = handle
        lastDelivered = ncReadFrom(0, delivered: latest(handle) ?? 0, now: Date().timeIntervalSinceReferenceDate)  // from now on, never the history
        read(show: false)  // the rows at that last moment count as seen
        watch()
        // Safety net, as in the spike: a file event can be missed (SQLite resets or replaces the WAL).
        // One indexed query every 2 s on this queue.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.read() }
        t.resume()
        poll = t
        log("nc: on")
    }

    private func watch() {
        watchers.forEach { $0.cancel() }
        watchers = []
        for suffix in ["", "-wal"] {
            let fd = Darwin.open(path + suffix, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
            src.setEventHandler { [weak self, weak src] in
                // A replaced file keeps this fd on the old one: watch the new file instead.
                if let e = src?.data, !e.isDisjoint(with: [.delete, .rename]) { self?.watch() }
                self?.read()
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
    }

    private func latest(_ handle: OpaquePointer?) -> Double? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "select coalesce(max(delivered_date), 0) from record", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_double(st, 0) : nil
    }

    private func read(show: Bool = true) {
        let sql = """
            select hex(r.uuid), a.identifier, r.delivered_date, r.data from record r
            left join app a on a.app_id = r.app_id where r.delivered_date >= ? order by r.delivered_date
            """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            log("nc: query failed: \(String(cString: sqlite3_errmsg(db)))"); return
        }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, lastDelivered)
        var found: [GzymsNotification] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let id = sqlite3_column_text(st, 0).map({ String(cString: $0) }), seen[id] == nil else { continue }
            let delivered = sqlite3_column_double(st, 2)
            seen[id] = delivered
            lastDelivered = ncReadFrom(lastDelivered, delivered: delivered, now: Date().timeIntervalSinceReferenceDate)
            guard let app = sqlite3_column_text(st, 1).map({ String(cString: $0) }), let bytes = sqlite3_column_blob(st, 3) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 3)))
            if let n = ncNotification(key: id, app: app, delivered: delivered, data: data) { found.append(n) }
            else { log("nc: row \(id) from \(app) has no text, skipped") }
        }
        seen = seen.filter { $0.value >= lastDelivered - 60 }
        guard show, !found.isEmpty else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver(found) } }
    }
}
