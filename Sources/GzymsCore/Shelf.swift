/// Files parked on the bar: where they lie, oldest first. Nothing is copied in. Dragging one out lets the place it
/// lands on copy or move the original, like Finder does.
public struct Shelf: Equatable, Sendable {
    public var paths: [String]
    public init(paths: [String] = []) { self.paths = paths }

    /// New files go to the end; one already on the shelf moves there instead of showing twice.
    public mutating func add(_ new: [String]) {
        var seen = Set<String>()
        let fresh = new.filter { seen.insert($0).inserted }
        paths.removeAll(where: seen.contains)
        paths += fresh
    }

    public mutating func remove(_ gone: [String]) { paths.removeAll(where: Set(gone).contains) }

    /// Drops what is no longer where it was: moved or deleted outside the shelf.
    public mutating func prune(exists: (String) -> Bool) { paths = paths.filter(exists) }
}
