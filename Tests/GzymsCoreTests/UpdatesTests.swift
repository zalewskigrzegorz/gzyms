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
