import Foundation

/// The bundle ids behind macOS' own camera and mic dots.
public struct SensorApps: Equatable, Sendable {
    public var camera: [String] = [], mic: [String] = []
    public init(camera: [String] = [], mic: [String] = []) { self.camera = camera; self.mic = mic }
}

/// Control Center's `sensor-indicators` log line `Active activity attributions changed to ["aud:<id>", "cam:<id>"]`;
/// nil = some other line. `loc:` (location) and the rest are dropped.
public func sensorApps(_ message: String) -> SensorApps? {
    let prefix = "Active activity attributions changed to "
    guard message.hasPrefix(prefix),
          let list = try? JSONSerialization.jsonObject(with: Data(message.dropFirst(prefix.count).utf8)) as? [String] else { return nil }
    var s = SensorApps()
    for item in list {
        if item.hasPrefix("cam:") { s.camera.append(String(item.dropFirst(4))) }
        if item.hasPrefix("aud:") { s.mic.append(String(item.dropFirst(4))) }
    }
    return s
}

/// The camera pill's tooltip; nil = nothing to show, so no pill. The app names come from Control Center's log.
/// `cameras` (names from CoreMediaIO) speak only when the log named no camera app, e.g. a camera on before Gzyms started.
public func sensorHelp(cameraApps: [String], micApps: [String], cameras: [String]) -> String? {
    var lines: [String] = []
    if !cameraApps.isEmpty { lines.append("\(listed(cameraApps)) \(cameraApps.count == 1 ? "is" : "are") using the camera.") }
    else if !cameras.isEmpty { lines.append("\(listed(cameras)) \(cameras.count == 1 ? "is" : "are") on.") }
    if !micApps.isEmpty { lines.append("\(listed(micApps)) \(micApps.count == 1 ? "is" : "are") using the mic.") }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
}

private func listed(_ names: [String]) -> String {
    names.count == 1 ? names[0] : "\(names.dropLast().joined(separator: ", ")) and \(names.last!)"
}
