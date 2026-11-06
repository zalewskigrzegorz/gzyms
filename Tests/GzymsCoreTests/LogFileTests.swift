import Foundation
import Testing
@testable import GzymsCore

@Test func theBarOwnsItsLogUnlessStderrIsAFile() {
    #expect(ownsLogFile(stderrMode: S_IFCHR | 0o666))  // /dev/null, a tty
    #expect(ownsLogFile(stderrMode: S_IFIFO))          // a pipe
    #expect(!ownsLogFile(stderrMode: S_IFREG | 0o644)) // install-dev.sh's StandardErrorPath
}
