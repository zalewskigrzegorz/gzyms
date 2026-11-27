import CoreGraphics
import GzymsCore
import Testing

private let dell = CGRect(x: -1920, y: 0, width: 1920, height: 1080), wide = CGRect(x: 0, y: 0, width: 3440, height: 1440)

@Test func ncHostGoesHomeOnlyWhileParkedAndTheSameSize() {
    let home = dell.origin
    // Live 2026-11-26: NC moved the host to the ultrawide itself; sending it to the Dell's corner put banners mid-screen.
    #expect(NCHome.target(parked: false, size: wide.size, home: home, homeSize: dell.size, screens: [wide, dell]) == nil)
    #expect(NCHome.target(parked: true, size: dell.size, home: home, homeSize: dell.size, screens: [wide, dell]) == home)
    #expect(NCHome.target(parked: true, size: wide.size, home: home, homeSize: dell.size, screens: [wide, dell]) == wide.origin)
    #expect(NCHome.target(parked: true, size: CGSize(width: 1, height: 1), home: home, homeSize: dell.size, screens: [wide]) == home)
}
