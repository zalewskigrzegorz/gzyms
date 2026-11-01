import CoreAudio
import Testing
@testable import GzymsCore

@Test func deviceKindByTransportOrName() {
    #expect(AudioDevice(id: 1, name: "Alex's AirPods Pro", transport: 0).kind == .headphones)
    #expect(AudioDevice(id: 2, name: "Sony WH", transport: kAudioDeviceTransportTypeBluetooth).kind == .headphones)
    #expect(AudioDevice(id: 3, name: "MacBook Pro Microphone", transport: kAudioDeviceTransportTypeBuiltIn).kind == .builtIn)
    #expect(AudioDevice(id: 4, name: "Alex's iPhone Microphone", transport: 0).kind == .iPhone)
    #expect(AudioDevice(id: 5, name: "Mic", transport: kAudioDeviceTransportTypeContinuityCaptureWireless).kind == .iPhone)
    #expect(AudioDevice(id: 6, name: "Shure MV7", transport: kAudioDeviceTransportTypeUSB).kind == .external)
}

@Test func micLevelScale() {
    #expect(Audio.level(rms: 0) == 0)
    #expect(Audio.level(rms: 1) == 1)
    #expect(Audio.level(rms: 0.001) == 0)  // -60 dBFS: silence
    #expect(abs(Audio.level(rms: 0.0316) - 0.5) < 0.01)  // -30 dBFS: half
}

@Test func stepCandidatesSkipCurrentAndBanned() {
    let ins = ["A", "B", "C", "D"].enumerated().map { AudioDevice(id: UInt32($0.offset + 1), name: $0.element, transport: 0) }
    func names(_ current: UInt32?, _ banned: Set<String>) -> [String] {
        AudioState(outputs: [], inputs: ins, output: nil, input: current, volume: nil, outputMuted: false, inputMuted: false)
            .candidates(input: true, banned: banned).map(\.name)
    }
    #expect(names(1, ["B"]) == ["C", "D"])
    #expect(names(3, ["B"]) == ["D", "A"])
    #expect(names(1, ["B", "C", "D"]) == [])
    #expect(names(2, ["B"]) == ["C", "D", "A"])  // the current one banned (macOS picked it): step off it
    #expect(names(nil, []) == ["A", "B", "C", "D"])
    #expect(names(1, ["b"]) == ["B", "C", "D"])  // names match exactly, like [audio.icons]
}

@Test func pickersHideBannedUnlessLive() {
    var a = AudioDevice(id: 1, name: "A", transport: 0), b = AudioDevice(id: 2, name: "B", transport: 0)
    a.banned = true; b.banned = false
    func shown(_ current: UInt32) -> [UInt32] {
        AudioState(outputs: [a, b], inputs: [], output: current, input: nil, volume: nil, outputMuted: false, inputMuted: false)
            .pickable(input: false).map(\.id)
    }
    #expect(shown(2) == [2])
    #expect(shown(1) == [1, 2])  // macOS picked the banned one: it stays visible
}

@Test func audioOfThisMac() {
    let s = Audio.read()
    #expect(!s.outputs.isEmpty)
    #expect(s.outputDevice != nil)
}
