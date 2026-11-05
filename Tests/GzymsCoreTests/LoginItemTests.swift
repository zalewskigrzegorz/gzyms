import GzymsCore
import Testing

@Test func releaseRegistersOnceAndRespectsOff() {
    #expect(loginItemStep(wanted: true, dev: false, status: .notRegistered) == .register)  // first launch
    #expect(loginItemStep(wanted: true, dev: false, status: .enabled) == .none)
    #expect(loginItemStep(wanted: false, dev: false, status: .enabled) == .unregister)  // switch off in Settings
    #expect(loginItemStep(wanted: false, dev: false, status: .notRegistered) == .none)
    // Turned off in System Settings → Login Items: not registered again behind the user's back.
    #expect(loginItemStep(wanted: true, dev: false, status: .requiresApproval) == .none)
    #expect(loginItemStep(wanted: true, dev: false, status: .notFound) == .none)
}

@Test func startAtLoginIsOnUnlessTheConfigSaysOff() {
    #expect(loadConfig(toml: nil).config.startAtLogin)
    #expect(!loadConfig(toml: "[bar]\nstart_at_login = false\n").config.startAtLogin)
}

@Test func devBuildNeverRegisters() {
    #expect(loginItemStep(wanted: true, dev: true, status: .notRegistered) == .none)
    #expect(loginItemStep(wanted: true, dev: true, status: .enabled) == .unregister)  // launchd and a login item: two at login
    #expect(loginItemStep(wanted: true, dev: true, status: .requiresApproval) == .unregister)
}
