import Foundation

/// Reloads `config.toml` when it changes: a hand edit, `chezmoi apply` (replaces the file) or the settings panel.
/// Watches the file (writes in place) and its folder (atomic replace = a rename there); a symlinked config is
/// watched at its target. Events are folded into one reload per 200 ms, and only a changed text counts.
final class ConfigWatcher: @unchecked Sendable {
    private let file: URL
    private let onChange: @MainActor () -> Void
    private let queue = DispatchQueue(label: "dev.gzyms.config")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var last: String?

    init(file: URL, onChange: @escaping @MainActor () -> Void) {
        self.file = file
        self.onChange = onChange
    }

    func start() { queue.async { self.last = self.read(); self.arm() } }

    private func read() -> String? { try? String(contentsOf: file, encoding: .utf8) }

    /// shortcut: a config folder that does not exist yet is not watched; `gzyms theme` and SIGHUP still reload.
    private func arm() {
        sources.forEach { $0.cancel() }
        sources = []
        let target = file.resolvingSymlinksInPath()
        var paths = [target.path, target.deletingLastPathComponent().path]
        if target != file { paths.append(file.deletingLastPathComponent().path) }
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .link], queue: queue)
            src.setEventHandler { [weak self] in self?.changed() }
            src.setCancelHandler { close(fd) }
            src.resume()
            sources.append(src)
        }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            arm()  // a replaced file is a new inode: watch that one from now on
            let text = read()
            guard text != last else { return }
            last = text
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onChange() } }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
