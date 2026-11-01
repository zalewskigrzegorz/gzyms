import Foundation
import GzymsCore
import GzymsUI

/// `gzyms completions <shell>` prints tab completion, `gzyms completions install [shell] [--yes]` puts it where that shell
/// reads it. Without a shell: every one this Mac has. Nothing is written without a yes.
enum CompletionsCommand {
    static func run(_ args: [String]) -> Never {
        if args.first == "install" { install(Array(args.dropFirst())) }
        guard let s = script(args.first ?? "") else { fail("usage: gzyms completions \(completionShells.joined(separator: "|")) | install [shell] [--yes]") }
        print(s, terminator: "")
        exit(0)
    }

    private static func script(_ shell: String) -> String? {
        completionScript(shell, extra: ["settings": SettingsTab.allCases.map(\.rawValue)])
    }

    private static func install(_ args: [String]) -> Never {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
        let named = args.filter { $0 != "--yes" }
        if let bad = named.first(where: { !completionShells.contains($0) }) {
            fail("gzyms completions install: no shell \"\(bad)\" (\(completionShells.joined(separator: ", ")))")
        }
        let nuDir = nuAutoloadDir()
        let found = completionShells.filter { sh in
            switch sh {
            case "nu": nuDir != nil
            case "fish": fm.fileExists(atPath: home.appendingPathComponent(".config/fish").path)
            default: fm.fileExists(atPath: home.appendingPathComponent(".\(sh)rc").path)
            }
        }
        let shells = named.isEmpty ? found : named
        guard !shells.isEmpty else { fail("gzyms completions install: no nu, fish, ~/.zshrc or ~/.bashrc here. Name a shell.") }
        let targets = shells.compactMap { sh in completionInstallTarget(shell: sh, home: home, nuAutoload: nuDir).map { (sh, $0) } }
        print("gzyms completions install writes:")
        for (_, t) in targets {
            switch t {
            case .file(let url): print("  \(url.path)")
            case .rcLine(let rc, let line): print("  \(rc.path): \(line)")
            }
        }
        if !args.contains("--yes") {
            print("write these? [y/N] ", terminator: "")
            guard readLine()?.lowercased().hasPrefix("y") == true else { print("nothing written"); exit(1) }
        }
        for (sh, t) in targets {
            do {
                switch t {
                case .file(let url):
                    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try (script(sh) ?? "").write(to: url, atomically: true, encoding: .utf8)
                case .rcLine(let rc, let line):
                    let text = (try? String(contentsOf: rc, encoding: .utf8)) ?? ""
                    if let new = addingRCLine(line, to: text) { try new.write(to: rc, atomically: true, encoding: .utf8) }
                }
            } catch { fail("gzyms completions install: could not write for \(sh): \(error.localizedDescription)") }
        }
        print("done. Open a new shell. nu and fish keep a copy: run this again after updating Gzyms.")
        exit(0)
    }

    /// Where nu itself autoloads from, or nil when nu is not installed.
    private static func nuAutoloadDir() -> URL? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["nu", "--no-config-file", "-c", "$nu.user-autoload-dirs | first"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
