/// When the bar steps aside for the macOS menu bar: hold ⌘ on the bar for `hold` seconds to yield,
/// keep the pointer off the bar strip for `leave` seconds to come back.
public struct MenuBarYield: Sendable {
    public static let hold = 0.3, leave = 0.5
    public private(set) var yielded = false
    private var since: Double?

    public init() {}

    /// One pointer sample; true when `yielded` just changed.
    public mutating func update(now: Double, inStrip: Bool, command: Bool) -> Bool {
        let counting = yielded ? !inStrip : (inStrip && command)
        guard counting else { since = nil; return false }
        let start = since ?? now
        since = start
        guard now - start >= (yielded ? Self.leave : Self.hold) else { return false }
        yielded.toggle()
        since = nil
        return true
    }
}
