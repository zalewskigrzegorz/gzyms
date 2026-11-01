import Foundation

/// The moments Gzyms makes a sound for, in the order Settings lists them.
public enum SoundEvent: String, CaseIterable, Sendable {
    case message, success, fail, waiting, armageddon

    /// What plays when `[sounds]` says nothing: the macOS sounds Gzyms always used.
    public var defaultChoice: String {
        switch self {
        case .message: "Pop"
        case .success: "Glass"
        case .fail: "Basso"
        case .waiting: "Submarine"
        case .armageddon: "Sosumi"
        }
    }

    /// Gzyms' own tone for it (prototype): frequency in Hz and length in seconds per note.
    public var tone: [(hz: Double, s: Double)] {
        switch self {
        case .message: [(880, 0.12), (1320, 0.18)]
        case .success: [(660, 0.1), (990, 0.1), (1320, 0.22)]
        case .fail: [(440, 0.18), (330, 0.3)]
        case .waiting: [(1046, 0.1), (1046, 0.1), (1568, 0.2)]
        case .armageddon: [(988, 0.14), (740, 0.14), (988, 0.14), (740, 0.14), (1318, 0.3)]
        }
    }
}

/// What one `[sounds]` value means: "gzyms" for the own tone, "cat" for the mascot's sound shipped with the app,
/// a path for a file, anything else a macOS sound name.
public enum SoundSource: Equatable, Sendable {
    case tone(SoundEvent), cat(SoundEvent), file(String), system(String)

    public static let gzyms = "gzyms", cat = "cat"

    public init(_ choice: String, event: SoundEvent) {
        if choice == Self.gzyms { self = .tone(event) }
        else if choice == Self.cat { self = .cat(event) }
        else if choice.hasPrefix("/") || choice.hasPrefix("~") { self = .file((choice as NSString).expandingTildeInPath) }
        else { self = .system(choice) }
    }
}

/// The macOS sounds Settings offers (the ones in /System/Library/Sounds).
public let macSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

/// The event a notification sounds as: its `sound` when that is an event name; without one, `message` for info and
/// warning, `fail` for error and critical (a plugin or script that names no sound still gets heard).
/// A `sound` that is no event plays as it is: a path to an audio file as that file, anything else as a macOS sound name.
public func soundSource(for n: GzymsNotification, choices: [SoundEvent: String]) -> SoundSource? {
    let s = n.sound ?? ([.error, .critical].contains(n.level) ? "fail" : "message")
    guard let e = SoundEvent(rawValue: s) else {
        let audio = ["mp3", "m4a", "wav", "aiff", "aif", "caf"].contains((s as NSString).pathExtension.lowercased())
        return (s.hasPrefix("/") || s.hasPrefix("~")) && audio ? SoundSource(s, event: .message) : .system(s)
    }
    return SoundSource(choices[e] ?? e.defaultChoice, event: e)
}

/// A tone as a 16-bit mono WAV, shaped like the prototype's Web Audio one: each note swells in for 20 ms and fades
/// out over its length, the next starts at 70 % of it.
public func toneWAV(_ notes: [(hz: Double, s: Double)], rate: Double = 44_100, volume: Double = 0.3) -> Data {
    var starts: [Double] = []
    var t = 0.0
    for n in notes { starts.append(t); t += n.s * 0.7 }
    let total = zip(starts, notes).map { $0 + $1.s }.max() ?? 0
    var samples = [Double](repeating: 0, count: Int(total * rate) + 1)
    for (start, n) in zip(starts, notes) {
        let first = Int(start * rate), count = Int(n.s * rate)
        for i in 0..<count {
            let x = Double(i) / rate
            // Exponential from 0.0001 up to 1 over 20 ms, then down to 0.0001 at the end (Web Audio's ramps).
            let env = x < 0.02 ? pow(10_000, x / 0.02) / 10_000 : pow(0.0001, (x - 0.02) / max(n.s - 0.02, 0.001))
            samples[first + i] += sin(2 * .pi * n.hz * x) * env * volume
        }
    }
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(bytes)
    for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
    return d
}
