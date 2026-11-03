import Foundation
import GzymsCore
import Network

/// Loopback-only HTTP for the browser userscript (assets/gzyms-media.user.js, `[hacks] browser_media`): GET serves
/// the script, POST /report takes a tab's media once a second and answers with the commands waiting for that tab.
/// Every web page can reach 127.0.0.1, so the server does nothing but play, pause, skip and focus media the
/// userscript reported. A report needs `X-Gzyms: 1`, which a page's own fetch() cannot send without a CORS
/// preflight this server never answers.
@MainActor
final class MediaServer {
    static let port: UInt16 = 47100
    static let scriptURL = URL(string: "http://127.0.0.1:\(port)/gzyms-media.user.js")!

    /// Listening now, for Settings → Hacks.
    private(set) var listening = false
    private var listener: NWListener?
    private var book = TabBook()
    private var pending: [String: [Command]] = [:]
    private var notes: [String: String] = [:]
    private var prune: Timer?
    private var live: [BrowserTab] = []
    private let deliver: ([BrowserTab]) -> Void

    private struct Command: Encodable { let i: Int, cmd: String }

    init(deliver: @escaping ([BrowserTab]) -> Void) { self.deliver = deliver }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        let l: NWListener
        do { l = try NWListener(using: params) } catch { log("media: no server on 127.0.0.1:\(Self.port): \(error)"); return }
        l.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready: self?.listening = true; log("media: userscript server on 127.0.0.1:\(Self.port)")
                // Gzyms Probe (or a second Gzyms) holds the port: the tabs stay out of the pill until it is free.
                case .failed(let e): self?.listening = false; self?.listener = nil; log("media: server stopped: \(e)")
                default: break
                }
            }
        }
        l.newConnectionHandler = { [weak self] c in
            MainActor.assumeIsolated {
                c.start(queue: .main)
                self?.read(c, Data())
            }
        }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
        listening = false
        prune?.invalidate(); prune = nil
        book = TabBook(); pending = [:]
        publish()
    }

    /// Waits for the tab's next report (within a second).
    func send(_ tab: String, media: Int, _ c: TabCommand) { pending[tab, default: []].append(Command(i: media, cmd: c.rawValue)) }

    private func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { c.cancel(); return }
                var b = buffer
                if let data { b.append(data) }
                switch LoopbackRequest.parse(b) {
                case .some(let request): c.send(content: self.answer(request), completion: .contentProcessed { _ in c.cancel() })
                case .none where done || error != nil: c.cancel()
                case .none: self.read(c, b)
                }
            }
        }
    }

    /// The whole response; nil request = one that could not be read.
    private func answer(_ r: LoopbackRequest?) -> Data {
        guard let r else { return http(400, "text/plain", Data()) }
        switch (r.method, r.path) {
        case ("GET", "/gzyms-media.user.js"):
            guard let url = Bundle.main.url(forResource: "gzyms-media.user", withExtension: "js"), let js = try? Data(contentsOf: url) else {
                return http(404, "text/plain", Data("no userscript in the bundle".utf8))
            }
            return http(200, "text/javascript; charset=utf-8", js)
        case ("POST", "/report") where r.headers["x-gzyms"] == "1":
            guard let tab = try? JSONDecoder().decode(BrowserTab.self, from: r.body) else { return http(400, "text/plain", Data()) }
            if tab.note != notes[tab.id] {
                if !tab.note.isEmpty { log("media: \(tab.host): \(tab.note)") }
                notes[tab.id] = tab.note
            }
            book.report(tab, now: Date().timeIntervalSince1970)
            publish()
            let commands = pending.removeValue(forKey: tab.id) ?? []
            return http(200, "application/json", (try? JSONEncoder().encode(["commands": commands])) ?? Data())
        default:
            return http(404, "text/plain", Data())
        }
    }

    /// Tells the bar when the tabs change; a tab that stops reporting leaves within 3 s, so a timer looks while any is up.
    private func publish() {
        let now = book.live(now: Date().timeIntervalSince1970)
        if now != live { live = now; deliver(now) }
        if live.isEmpty { prune?.invalidate(); prune = nil }
        else if prune == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.publish() } }
            RunLoop.main.add(t, forMode: .common)
            prune = t
        }
    }

    private func http(_ code: Int, _ type: String, _ body: Data) -> Data {
        Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
    }
}
