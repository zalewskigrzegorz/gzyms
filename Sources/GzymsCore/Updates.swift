/// Where Homebrew keeps a cask's receipt: `<prefix>/Caskroom/<token>`, `/opt/homebrew` on Apple silicon, `/usr/local` on Intel.
/// Looked up on disk, so Gzyms never runs `brew` (slow, and not there for a website install).
public let homebrewCaskrooms = ["/opt/homebrew/Caskroom/gzyms", "/usr/local/Caskroom/gzyms"]

public func installedWithHomebrew(exists: (String) -> Bool) -> Bool {
    homebrewCaskrooms.contains(where: exists)
}

/// Whether Sparkle checks for updates by itself. `chosen` is `[updates] automatic`, written only when the user
/// went against the default: on for a website install, off for Homebrew, which updates the app (`brew upgrade gzyms`).
public func automaticUpdates(chosen: Bool?, homebrew: Bool) -> Bool { chosen ?? !homebrew }

/// Homebrew users hear about a version once: it must be newer than this build and than the last one told (`isNewer`).
public func shouldTellUpdate(found: String, current: String, told: String?) -> Bool {
    isNewer(found, than: current) && (told.map { isNewer(found, than: $0) } ?? true)
}

public func releaseURL(version: String) -> String { "https://github.com/zalewskigrzegorz/gzyms/releases/tag/v\(version)" }
