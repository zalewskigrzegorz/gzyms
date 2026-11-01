import AVFoundation
import GzymsCore

/// Mute that sticks: the device's own mute, or input volume 0 held down against apps (Zoom, Meet)
/// that raise it again. Unmute brings back the volume from before.
@MainActor
final class MicMute {
    private var held: UInt32?
    private var before: Float = 1
    private var stopWatching: (() -> Void)?

    func toggle(_ audio: AudioState?) {
        guard let id = audio?.input else { return }
        audio?.inputMuted == true ? unmute(id) : mute(id)
    }

    private func mute(_ id: UInt32) {
        if Audio.setInputMute(true, device: id) { return }
        before = Audio.inputVolume(id).flatMap { $0 > 0 ? $0 : nil } ?? 1
        Audio.setInputVolume(0, device: id)
        held = id
        stopWatching = Audio.onInputVolumeChange(id) { [weak self] in MainActor.assumeIsolated { self?.holdDown() } }
    }

    private func holdDown() {
        guard let id = held, (Audio.inputVolume(id) ?? 0) > 0 else { return }
        Audio.setInputVolume(0, device: id)
        log("mic mute: another app raised the input volume, set back to 0")
    }

    private func unmute(_ id: UInt32) {
        if Audio.setInputMute(false, device: id) { return }
        stopWatching?(); stopWatching = nil
        // After a Gzyms restart nothing is held, so there is no "before": full volume.
        Audio.setInputVolume(held == id ? before : 1, device: id)
        held = nil
    }
}

/// Live input level for the mic popup. Runs only while the popup is open (macOS shows its orange dot then).
/// The engine itself lives on `Audio.queue`: starting it on an iPhone mic blocks for up to 4 s.
@MainActor
final class MicMeter {
    private let box = MeterEngine()
    /// The popup or the preview still wants a level: a device that refused to start is tried again.
    private var wanted = false
    /// Bumped by every start, stop and restart, so a late retry or change notice from before does nothing.
    private var generation = 0
    var onLevel: (Double) -> Void = { _ in }

    func start() { wanted = true; generation += 1; run(generation) }

    private func run(_ gen: Int) {
        guard wanted, gen == generation else { return }
        let tap = Self.tap { [weak self] level in if self?.wanted == true { self?.onLevel(level) } }
        let changed: @MainActor () -> Void = { [weak self] in self?.restart(gen) }
        let failed: @MainActor (String) -> Void = { [weak self] why in self?.retry(why, gen) }
        let box = box
        Audio.queue.async { box.start(tap: tap, changed: changed, failed: failed) }
    }

    /// A new default input (AirPods, a mic picked with M) stops the engine; start over on the new device.
    private func restart(_ gen: Int) {
        guard wanted, gen == generation else { return }
        log("mic meter: input changed, restarting")
        halt()
        run(generation)
    }

    /// A mic still switching refuses for a moment (-10868); one second later it usually starts.
    private func retry(_ why: String, _ gen: Int) {
        guard wanted, gen == generation else { return }
        log("mic meter: \(why), again in 1 s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.run(gen) }
    }

    /// Built outside the main actor on purpose: AVAudio calls the tap on its own audio thread, and a closure
    /// written inside a @MainActor method inherits that isolation and traps there (crash 2026-10-31 02:39).
    private nonisolated static func tap(_ report: @escaping @MainActor (Double) -> Void) -> SendableTap {
        { buffer, _ in
            guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
            let level = Audio.level(rms: (sum / Float(buffer.frameLength)).squareRoot())
            DispatchQueue.main.async { report(level) }
        }
    }

    func stop() { wanted = false; halt() }

    /// Serial queue: a start still queued or running finishes first, then this stops it.
    private func halt() {
        generation += 1
        let box = box
        Audio.queue.async { box.halt() }
        onLevel(0)
    }
}

private typealias SendableTap = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

/// Touched only on `Audio.queue`.
private final class MeterEngine: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var changed: (any NSObjectProtocol)?

    func start(tap: @escaping SendableTap, changed onChange: @escaping @MainActor () -> Void,
               failed: @escaping @MainActor (String) -> Void) {
        guard engine == nil else { return }
        let e = AVAudioEngine()
        let input = e.inputNode
        // nil = the format the device has now: a format read a moment earlier may already be stale while M
        // steps through mics, and a mismatch raises an exception Swift cannot catch (crash 2026-11-01 18:40).
        guard input.outputFormat(forBus: 0).sampleRate > 0 else { DispatchQueue.main.async { failed("no input format yet") }; return }
        input.installTap(onBus: 0, bufferSize: 2048, format: nil, block: tap)
        do { try e.start() } catch {
            input.removeTap(onBus: 0)
            let why = "\(error)"
            DispatchQueue.main.async { failed(why) }
            return
        }
        engine = e
        changed = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: nil) { _ in
            DispatchQueue.main.async { onChange() }
        }
    }

    func halt() {
        if let c = changed { NotificationCenter.default.removeObserver(c); changed = nil }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}
