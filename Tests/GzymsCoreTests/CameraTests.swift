import Testing
@testable import GzymsCore

@Test func sensorAppsReadsControlCentersLogLine() {
    // Lines as macOS 27.2's Control Center logs them, Photo Booth open while Spotifast holds the mic.
    #expect(sensorApps(#"Active activity attributions changed to ["aud:rocks.spotifast.Spotifast", "cam:com.apple.PhotoBooth"]"#)
        == SensorApps(camera: ["com.apple.PhotoBooth"], mic: ["rocks.spotifast.Spotifast"]))
    #expect(sensorApps(#"Active activity attributions changed to ["loc:com.apple.findmy", "aud:rocks.spotifast.Spotifast"]"#)
        == SensorApps(mic: ["rocks.spotifast.Spotifast"]))
    #expect(sensorApps("Active activity attributions changed to []") == SensorApps())
    #expect(sensorApps(#"Recent activity attributions changed to ["cam:com.apple.PhotoBooth"]"#) == nil)
    #expect(sensorApps("Sorted active attributions from SystemStatus update: [[aud] Spotifast (rocks.spotifast.Spotifast), [cam] Photo Booth (com.apple.PhotoBooth)]") == nil)
}

@Test func sensorHelpNamesTheAppsAndFallsBackToCameras() {
    #expect(sensorHelp(cameraApps: [], micApps: [], cameras: []) == nil)
    #expect(sensorHelp(cameraApps: ["Photo Booth"], micApps: [], cameras: ["FaceTime HD Camera"]) == "Photo Booth is using the camera.")
    #expect(sensorHelp(cameraApps: ["Photo Booth", "Zoom", "FaceTime"], micApps: [], cameras: []) == "Photo Booth, Zoom and FaceTime are using the camera.")
    #expect(sensorHelp(cameraApps: [], micApps: [], cameras: ["FaceTime HD Camera"]) == "FaceTime HD Camera is on.")
    #expect(sensorHelp(cameraApps: [], micApps: [], cameras: ["FaceTime HD Camera", "iPhone Camera"]) == "FaceTime HD Camera and iPhone Camera are on.")
    #expect(sensorHelp(cameraApps: ["Photo Booth"], micApps: ["Spotifast"], cameras: []) == "Photo Booth is using the camera.\nSpotifast is using the mic.")
    #expect(sensorHelp(cameraApps: [], micApps: ["Spotifast", "Zoom"], cameras: []) == "Spotifast and Zoom are using the mic.")
}
