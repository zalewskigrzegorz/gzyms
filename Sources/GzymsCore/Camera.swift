/// The camera pill's tooltip for the cameras running now; nil = none, so no pill.
/// macOS does not tell an app which app holds a camera, so the pill names the camera, not the app.
public func cameraHelp(_ running: [String]) -> String? {
    switch running.count {
    case 0: nil
    case 1: "\(running[0]) is on."
    default: "\(running.dropLast().joined(separator: ", ")) and \(running.last!) are on."
    }
}
