import Foundation
import Testing
@testable import GzymsCore

@Test func aChoiceReadsAsToneFileOrMacSound() {
    #expect(SoundSource("gzyms", event: .fail) == .tone(.fail))
    #expect(SoundSource("/tmp/a.wav", event: .fail) == .file("/tmp/a.wav"))
    #expect(SoundSource("~/a.wav", event: .fail) == .file(NSHomeDirectory() + "/a.wav"))
    #expect(SoundSource("Hero", event: .fail) == .system("Hero"))
}

@Test func theConfigPicksTheEventsSound() {
    var n = GzymsNotification(id: "a", app: nil, level: .info, title: "t", subtitle: nil, body: nil, link: nil, altLink: nil,
                              sound: "success", at: Date())
    #expect(soundSource(for: n, choices: [.success: "gzyms"]) == .tone(.success))
    n.sound = "Funk"
    #expect(soundSource(for: n, choices: [.success: "gzyms"]) == .system("Funk"))
    n.sound = "~/s/pr-ci_fail.mp3"  // a plugin's own sound file
    #expect(soundSource(for: n, choices: [:]) == .file(NSHomeDirectory() + "/s/pr-ci_fail.mp3"))
    n.sound = "/etc/passwd"  // a path, but no audio file: a macOS name that plays nothing
    #expect(soundSource(for: n, choices: [:]) == .system("/etc/passwd"))
    let load = loadConfig(toml: "[sounds]\nmessage = \"gzyms\"\nbeep = \"Pop\"")
    #expect(load.config.sounds == [.message: "gzyms"])
    #expect(load.problems.count == 1)
}

@Test func aToneIsAPlayableWAV() {
    let d = toneWAV(SoundEvent.message.tone)
    #expect(d.prefix(4) == Data("RIFF".utf8))
    // 0.12 * 0.7 + 0.18 s at 44.1 kHz, 2 bytes a sample, after a 44 byte header.
    #expect(abs(d.count - 44 - Int((0.084 + 0.18) * 44_100) * 2) < 8)
}

@Test func catIsTheMascotsSound() {
    #expect(SoundSource("cat", event: .waiting) == .cat(.waiting))
    for e in SoundEvent.allCases {
        #expect(FileManager.default.fileExists(atPath: "assets/sounds/cat-\(e.rawValue).mp3"), "missing cat-\(e.rawValue).mp3")
    }
}
