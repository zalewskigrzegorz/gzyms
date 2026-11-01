import GzymsCore
import Testing

@Test func shelfKeepsOneOfEachFileNewestLast() {
    var s = Shelf(paths: ["/a", "/b"])
    s.add(["/c", "/a", "/c"])
    #expect(s.paths == ["/b", "/c", "/a"])
    s.remove(["/b", "/x"])
    #expect(s.paths == ["/c", "/a"])
    s.prune { $0 != "/c" }
    #expect(s.paths == ["/a"])
}
