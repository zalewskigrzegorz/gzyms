import Testing
@testable import GzymsCore

@Test func onlyAGrantThatWasOnCountsAsRevoked() {
    let on = [GrantState(grant: .accessibility, granted: true), GrantState(grant: .fullDiskAccess, granted: false)]
    let off = [GrantState(grant: .accessibility, granted: false), GrantState(grant: .fullDiskAccess, granted: false)]
    #expect(revokedGrants(before: on, after: off) == [.accessibility])
    #expect(revokedGrants(before: off, after: off) == [])
    #expect(revokedGrants(before: [], after: off) == [])  // first check at launch: the wizard, not the ⚠
}
