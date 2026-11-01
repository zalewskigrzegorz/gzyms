import Foundation
import Testing
@testable import GzymsCore

@Test func configDirUsesXDGWhenSet() {
    #expect(Paths.configDir(env: ["XDG_CONFIG_HOME": "/x", "HOME": "/h"]).path == "/x/gzyms")
}

@Test func configDirDefaultsToDotConfig() {
    #expect(Paths.configDir(env: ["HOME": "/h"]).path == "/h/.config/gzyms")
}

@Test func logsDirIsInLibraryLogs() {
    #expect(Paths.logsDir(home: URL(fileURLWithPath: "/h")).path == "/h/Library/Logs/Gzyms")
}
