import Foundation

/// A released app starts with stderr on /dev/null, so the bar opens its own log. launchd already hands
/// install-dev.sh's agent a regular file: that one stays as it is.
public func ownsLogFile(stderrMode: mode_t) -> Bool { stderrMode & S_IFMT != S_IFREG }

/// Past this size `gzyms.log` moves to `gzyms.log.1`, so a log never takes more than about twice it.
public let logCap: UInt64 = 5_000_000
