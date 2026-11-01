import Foundation
import GzymsCore

/// Watches HyprMac's folder (state.json is replaced atomically, so watching the file itself would go deaf).
@MainActor
final class StateWatcher {
    private let url: URL
    private let onChange: (StateRead) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var previous: HyprMacState?

    init(url: URL, onChange: @escaping (StateRead) -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        read()
        let fd = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { log("state watcher: cannot watch \(url.deletingLastPathComponent().path)"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func read() {
        let result = readState(try? Data(contentsOf: url), previous: previous)
        switch result {
        case .fresh(let s): previous = s
        case .stale(_, let reason): log("state.json stale: \(reason)")
        case .none: break
        }
        onChange(result)
    }
}
