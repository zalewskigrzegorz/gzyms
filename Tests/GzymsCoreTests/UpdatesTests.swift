import Testing
@testable import GzymsCore

@Test func aCaskroomMeansHomebrew() {
    #expect(installedWithHomebrew { $0 == "/opt/homebrew/Caskroom/gzyms" })
    #expect(installedWithHomebrew { $0 == "/usr/local/Caskroom/gzyms" })
    #expect(!installedWithHomebrew { _ in false })
    #expect(!installedWithHomebrew { $0 == "/opt/homebrew/Caskroom/clop" })
}

@Test func updatesAreAutomaticUnlessHomebrewOrChosenOtherwise() {
    #expect(automaticUpdates(chosen: nil, homebrew: false))
    #expect(!automaticUpdates(chosen: nil, homebrew: true))
    #expect(automaticUpdates(chosen: true, homebrew: true))
    #expect(!automaticUpdates(chosen: false, homebrew: false))
}

@Test func updatesAutomaticParsesAndIsUnsetByDefault() {
    #expect(loadConfig(toml: nil).config.updatesAutomatic == nil)
    let on = loadConfig(toml: "[updates]\nautomatic = true\n")
    #expect(on.config.updatesAutomatic == true)
    #expect(on.problems.isEmpty)
    #expect(loadConfig(toml: "[updates]\nautomatic = false\n").config.updatesAutomatic == false)
}

@Test func anUpdateIsToldOncePerVersion() {
    #expect(shouldTellUpdate(found: "0.0.3", current: "0.0.2", told: nil))
    #expect(!shouldTellUpdate(found: "0.0.3", current: "0.0.2", told: "0.0.3"))
    #expect(shouldTellUpdate(found: "0.0.4", current: "0.0.2", told: "0.0.3"))
    // Already on it (brew upgraded before the restart), or an older item in the feed.
    #expect(!shouldTellUpdate(found: "0.0.2", current: "0.0.2", told: nil))
    #expect(!shouldTellUpdate(found: "0.0.3", current: "0.0.4", told: nil))
}

@Test func theReleaseLinkUsesTheTag() {
    #expect(releaseURL(version: "0.0.3") == "https://github.com/zalewskigrzegorz/gzyms/releases/tag/v0.0.3")
}
