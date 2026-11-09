import Testing
@testable import GzymsCore

@Test func cameraHelpNamesTheRunningCameras() {
    #expect(cameraHelp([]) == nil)
    #expect(cameraHelp(["FaceTime HD Camera"]) == "FaceTime HD Camera is on.")
    #expect(cameraHelp(["FaceTime HD Camera", "iPhone Camera"]) == "FaceTime HD Camera and iPhone Camera are on.")
    #expect(cameraHelp(["A", "B", "C"]) == "A, B and C are on.")
}
