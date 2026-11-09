import CoreMediaIO
import GzymsCore

/// The apps using the camera and the mic, from Control Center's log (the same names as macOS' own dots), and
/// the names of the cameras running in any process, from CoreMediaIO, for when the log has said nothing yet.
/// Gzyms' own meeting preview counts too.
/// shortcut: a wired iPhone's screen capture device counts as a camera while QuickTime records it; filter by
/// AVCaptureDevice ids if that shows up.
@MainActor
final class CameraWatcher {
    private let onChange: ([String]) -> Void
    private let onApps: (SensorApps) -> Void
    private var sensors: LogStream?
    private var watched: [CMIOObjectID] = []
    private var on = false
    private var last: [String] = []
    /// One block for every listener, so the same block removes them. It only says "look again": it also fires
    /// when nothing changed (Apple forums 697124), so every call re-reads the state.
    private lazy var listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.refresh() }
    }

    init(onChange: @escaping ([String]) -> Void, onApps: @escaping (SensorApps) -> Void) { self.onChange = onChange; self.onApps = onApps }

    func start() {
        guard !on else { return }
        on = true
        var addr = Self.address(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, .main, listener)
        refresh()
        let filter = #"--predicate 'subsystem == "com.apple.controlcenter" AND category == "sensor-indicators" AND eventMessage BEGINSWITH "Active activity attributions"'"#
        sensors = LogStream(name: "sensors", filter: filter) { [weak self] message in
            guard let apps = sensorApps(message) else { return }
            log("sensors: camera \(apps.camera), mic \(apps.mic)")
            self?.onApps(apps)
        }
        sensors?.start()
    }

    func stop() {
        guard on else { return }
        on = false
        var addr = Self.address(kCMIOHardwarePropertyDevices)
        CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, .main, listener)
        unwatch()
        report([])
        sensors?.stop()
        sensors = nil
        onApps(SensorApps())
    }

    private func refresh() {
        guard on else { return }
        let devices = Self.devices()
        if devices != watched {
            unwatch()
            var addr = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            for d in devices { CMIOObjectAddPropertyListenerBlock(d, &addr, .main, listener) }
            watched = devices
        }
        report(devices.filter(Self.isRunning).map(Self.name))
    }

    private func unwatch() {
        var addr = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for d in watched { CMIOObjectRemovePropertyListenerBlock(d, &addr, .main, listener) }
        watched = []
    }

    private func report(_ names: [String]) {
        guard names != last else { return }
        last = names
        log(names.isEmpty ? "camera: off" : "camera: on (\(names.joined(separator: ", ")))")
        onChange(names)
    }

    // MARK: - CoreMediaIO plumbing

    private static func address(_ sel: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(sel), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func devices() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isRunning(_ id: CMIOObjectID) -> Bool {
        var addr = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr && value != 0
    }

    private static func name(_ id: CMIOObjectID) -> String {
        var addr = address(kCMIOObjectPropertyName)
        var ref: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &ref) == noErr,
              let name = ref?.takeRetainedValue() else { return "A camera" }
        return name as String
    }
}
