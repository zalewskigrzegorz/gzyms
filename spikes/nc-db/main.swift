// Spike S1: can Gzyms read macOS notifications live? Throwaway, never imported by the product.
// Prints only app ids, timings and which fields exist — never notification text.
import Foundation
import SQLite3

let home = FileManager.default.homeDirectoryForCurrentUser.path
let dbPath = home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
let logURL = URL(fileURLWithPath: "/tmp/gzyms-spike-nc.log")
FileManager.default.createFile(atPath: logURL.path, contents: nil)
let logHandle = try! FileHandle(forWritingTo: logURL)
func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    logHandle.write(line.data(using: .utf8)!)
    print(line, terminator: "")
}

var db: OpaquePointer?
let rc = sqlite3_open_v2("file:\(dbPath)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
if rc != SQLITE_OK {
    log("OPEN FAILED rc=\(rc) msg=\(String(cString: sqlite3_errmsg(db)))")
    exit(1)
}
log("opened \(dbPath)")

func fields(_ blob: Data) -> String {
    guard let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) else { return "blob=undecodable" }
    guard let dict = plist as? [String: Any] else { return "blob=\(type(of: plist))" }
    var out = ["top=\(dict.keys.sorted().joined(separator: ","))"]
    if let req = dict["req"] as? [String: Any] {
        out.append("req=\(req.keys.sorted().joined(separator: ","))")
        for k in ["titl", "subt", "body"] { out.append("\(k)=\((req[k] as? String)?.count ?? -1)ch") }
    }
    return out.joined(separator: " ")
}

var lastID: Int64 = -1
func poll(_ reason: String) {
    let sql = "select r.rec_id, a.identifier, r.delivered_date, r.data from record r left join app a on a.app_id = r.app_id where r.rec_id > ? order by r.rec_id"
    var st: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
        log("PREPARE FAILED \(String(cString: sqlite3_errmsg(db)))"); return
    }
    sqlite3_bind_int64(st, 1, lastID)
    var rows: [(Int64, String, Double, Data)] = []
    while sqlite3_step(st) == SQLITE_ROW {
        let id = sqlite3_column_int64(st, 0)
        let app = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? "?"
        let delivered = sqlite3_column_double(st, 2)
        let bytes = sqlite3_column_blob(st, 3); let n = Int(sqlite3_column_bytes(st, 3))
        let data = bytes.map { Data(bytes: $0, count: n) } ?? Data()
        rows.append((id, app, delivered, data))
    }
    sqlite3_finalize(st)
    let first = lastID < 0
    if first { log("existing rows: \(rows.count)") }
    for (i, r) in rows.enumerated() where !first || i >= rows.count - 3 {
        let delay = Date().timeIntervalSinceReferenceDate - r.2
        log("\(first ? "old" : "NEW") rec=\(r.0) app=\(r.1) delay=\(String(format: "%.1f", delay))s via=\(reason) \(fields(r.3))")
    }
    if let last = rows.last { lastID = last.0 }
}

poll("start")
var sources: [DispatchSourceFileSystemObject] = []
for suffix in ["", "-wal"] {
    let fd = open(dbPath + suffix, O_EVTONLY)
    guard fd >= 0 else { log("cannot watch \(dbPath + suffix)"); continue }
    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
    src.setEventHandler { poll("fs\(suffix)") }
    src.resume(); sources.append(src)
}
// Safety net: also poll every 2 s, to compare against file events.
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in poll("timer") }
log("watching; send notifications now")
RunLoop.main.run()
