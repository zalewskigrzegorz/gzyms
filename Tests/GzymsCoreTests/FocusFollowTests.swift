import Foundation
import Testing
@testable import GzymsCore

@Test func activeFocusModesReadsTheModeOfEachRecord() {
    let on = Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}],"storeInvalidationRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.sleep.sleep-mode"}}]}]}"#.utf8)
    #expect(activeFocusModes(assertions: on) == ["com.apple.focus.work"])
    #expect(activeFocusModes(assertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)).isEmpty)
    #expect(activeFocusModes(assertions: Data("nope".utf8)).isEmpty)
}

@Test func focusModesListsNamesSorted() {
    let json = Data(#"{"data":[{"modeConfigurations":{"com.apple.focus.work":{"mode":{"name":"Work"}},"com.apple.donotdisturb.mode.default":{"mode":{"name":"Do Not Disturb"}},"broken":{}}}]}"#.utf8)
    #expect(focusModes(modeConfigurations: json) == [FocusMode(id: FocusFollow.dndMode, name: "Do Not Disturb"), FocusMode(id: "com.apple.focus.work", name: "Work")])
}

@Test func followFocusIsRead() {
    #expect(GzymsConfig.defaults.followFocus == [FocusFollow.dndMode])
    #expect(loadConfig(toml: "[dnd]\nfollow_focus = [\"com.apple.focus.work\"]\n").config.followFocus == ["com.apple.focus.work"])
    #expect(loadConfig(toml: "[dnd]\nfollow_focus = []\n").config.followFocus.isEmpty)
}

@Test func aFocusTurnsDNDOnAndOff() {
    var f = FocusFollow()
    #expect(f.focus(true, dndOn: false) == .turnOn)
    #expect(f.focus(true, dndOn: true) == nil)  // the same Focus read again
    #expect(f.focus(false, dndOn: true) == .turnOff)
    #expect(f.focus(false, dndOn: false) == nil)
}

@Test func aFocusLeavesDNDTurnedOnByHand() {
    var f = FocusFollow()
    #expect(f.focus(true, dndOn: true) == nil)
    #expect(f.focus(false, dndOn: true) == nil)
}

@Test func dndTurnedOffByHandStaysOffUntilTheNextFocus() {
    var f = FocusFollow()
    #expect(f.focus(true, dndOn: false) == .turnOn)
    f.handSet()
    #expect(f.focus(true, dndOn: false) == nil)
    #expect(f.focus(false, dndOn: false) == nil)
    #expect(f.focus(true, dndOn: false) == .turnOn)
}

@Test func dndSetByHandDuringAFocusOutlivesIt() {
    var f = FocusFollow()
    #expect(f.focus(true, dndOn: false) == .turnOn)
    f.handSet()  // e.g. "1 h" from the moon pill
    #expect(f.focus(false, dndOn: true) == nil)
}
