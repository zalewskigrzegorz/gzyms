import AudioToolbox
import CoreAudio
import Foundation

public struct AudioDevice: Equatable, Sendable {
    /// Raw values are the names `[audio.icons]` takes.
    public enum Kind: String, CaseIterable, Sendable {
        case builtIn = "laptop", iPhone = "phone", headphones, monitor, camera, mic, speaker, external
    }

    public var id: UInt32
    public var name: String
    public var transport: UInt32
    /// From `[audio.icons]`, for hardware that reports an odd transport.
    public var kindOverride: Kind?
    /// In `[audio] banned`: the popups dim it.
    public var banned = false
    public init(id: UInt32, name: String, transport: UInt32) { self.id = id; self.name = name; self.transport = transport }

    /// What it is at a glance, so the pill can show a laptop, an iPhone or headphones instead of one generic mic.
    public var kind: Kind {
        if let kindOverride { return kindOverride }
        let n = name.lowercased()
        if [kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless].contains(transport)
            || n.contains("iphone") { return .iPhone }
        if [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport)
            || ["airpods", "headphone", "buds", "beats"].contains(where: n.contains) { return .headphones }
        if transport == kAudioDeviceTransportTypeBuiltIn { return .builtIn }
        if [kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort].contains(transport) { return .monitor }
        if ["camera", "webcam", "insta360", "facetime"].contains(where: n.contains) { return .camera }
        return .external
    }

    public var isHeadphones: Bool { kind == .headphones }
}

public struct AudioState: Equatable, Sendable {
    public var outputs: [AudioDevice], inputs: [AudioDevice]
    public var output: UInt32?, input: UInt32?
    /// 0...1, nil when the device has no software volume.
    public var volume: Double?
    public var outputMuted: Bool, inputMuted: Bool

    public init(outputs: [AudioDevice], inputs: [AudioDevice], output: UInt32?, input: UInt32?, volume: Double?, outputMuted: Bool, inputMuted: Bool) {
        self.outputs = outputs; self.inputs = inputs; self.output = output; self.input = input
        self.volume = volume; self.outputMuted = outputMuted; self.inputMuted = inputMuted
    }

    public var outputDevice: AudioDevice? { outputs.first { $0.id == output } }
    public var inputDevice: AudioDevice? { inputs.first { $0.id == input } }

    /// The pickers' rows: banned devices left out, unless macOS made one the default (then the user sees what is live).
    public func pickable(input isInput: Bool) -> [AudioDevice] {
        (isInput ? inputs : outputs).filter { !$0.banned || $0.id == (isInput ? input : output) }
    }

    /// What M or S tries next, in order: the devices after the current one, wrapping round, minus it and `[audio] banned`.
    public func candidates(input isInput: Bool, banned: Set<String>) -> [AudioDevice] {
        let devices = isInput ? inputs : outputs
        let current = isInput ? input : output
        let start = (devices.firstIndex { $0.id == current } ?? -1) + 1
        return (0..<devices.count).map { devices[(start + $0) % devices.count] }
            .filter { $0.id != current && !banned.contains($0.name) }
    }
}

/// CoreAudio property reads and writes. No subprocess, cheap enough for every 2 s.
public enum Audio {
    public static func read() -> AudioState {
        var outs: [AudioDevice] = [], ins: [AudioDevice] = []
        for id in devices() {
            let d = AudioDevice(id: id, name: name(id) ?? "Device \(id)", transport: value(id, kAudioDevicePropertyTransportType, as: UInt32(0)) ?? 0)
            // AVAudioEngine's own helper while the mic meter runs: never a real choice, and picking it changes nothing,
            // so M and S got stuck on it.
            if d.transport == kAudioDeviceTransportTypeAggregate, d.name.hasPrefix("CADefaultDeviceAggregate") { continue }
            if hasStreams(id, kAudioObjectPropertyScopeOutput) { outs.append(d) }
            if hasStreams(id, kAudioObjectPropertyScopeInput) { ins.append(d) }
        }
        let out = value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID(0))
        let inp = value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, as: AudioObjectID(0))
        let vol = out.flatMap { value($0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, as: Float32(0)) }
        return AudioState(outputs: outs, inputs: ins, output: out, input: inp, volume: vol.map(Double.init),
                          outputMuted: out.flatMap { value($0, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, as: UInt32(0)) } == 1,
                          inputMuted: inp.map(inputMuted) ?? false)
    }

    /// Every default-device write and mic meter start goes here: an iPhone mic takes up to 4 s to answer,
    /// and on main that froze the bar (main_thread_stall 4097 ms, 2026-11-01). Serial, so held M presses stay in order.
    public static let queue = DispatchQueue(label: "gzyms.audio", qos: .userInitiated)

    /// `setDefault` on `queue`, the result back on main.
    public static func setDefaultAsync(_ id: UInt32, input: Bool, then: @escaping @MainActor (Bool) -> Void) {
        queue.async {
            let ok = setDefault(id, input: input)
            DispatchQueue.main.async { then(ok) }
        }
    }

    @discardableResult
    public static func setDefault(_ id: UInt32, input: Bool) -> Bool {
        var dev = AudioObjectID(id)
        return set(AudioObjectID(kAudioObjectSystemObject), input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal, &dev)
    }

    /// The device's own input mute; false when it has none (the MacBook mic), then the caller zeroes the volume.
    @discardableResult
    public static func setInputMute(_ muted: Bool, device id: UInt32) -> Bool {
        var m: UInt32 = muted ? 1 : 0
        return set(id, kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, &m)
    }

    public static func inputVolume(_ id: UInt32) -> Float? {
        value(id, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, as: Float32(0))
    }

    public static func setInputVolume(_ v: Float, device id: UInt32) {
        var v = v
        set(id, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, &v)
    }

    /// Calls `handler` on the main queue whenever the device's input volume changes; returns the remover.
    public static func onInputVolumeChange(_ id: UInt32, _ handler: @escaping @Sendable () -> Void) -> () -> Void {
        var addr = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main, block)
        return {
            var addr = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput)
            AudioObjectRemovePropertyListenerBlock(id, &addr, DispatchQueue.main, block)
        }
    }

    /// Mic level 0...1 from the RMS of a buffer, on a -60...0 dBFS scale like most meters.
    public static func level(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        return min(1, max(0, (Double(20 * log10(rms)) + 60) / 60))
    }

    static func inputMuted(_ id: UInt32) -> Bool {
        if let m = value(id, kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, as: UInt32(0)) { return m == 1 }
        return value(id, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, as: Float32(1)) == 0
    }

    // MARK: - CoreAudio plumbing

    private static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector,
                                 _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as initial: T) -> T? {
        var addr = address(sel, scope)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    @discardableResult
    private static func set<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ v: inout T) -> Bool {
        var addr = address(sel, scope)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &addr), AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    private static func devices() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasStreams(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func name(_ id: AudioObjectID) -> String? {
        var addr = address(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
