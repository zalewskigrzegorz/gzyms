import Foundation
import Testing
@testable import GzymsCore

/// The Keychain stand-in: a dictionary, or a store that refuses everything.
final class MemoryStore: SecretStore {
    var values: [String: String]
    var broken = false
    struct Refused: Error, CustomStringConvertible { var description: String { "refused" } }
    init(_ values: [String: String] = [:]) { self.values = values }
    func get(_ account: String) throws -> String? { if broken { throw Refused() }; return values[account] }
    func set(_ value: String, for account: String) throws { if broken { throw Refused() }; values[account] = value }
    func delete(_ account: String) throws { if broken { throw Refused() }; values[account] = nil }
}

@Test func phonePushReadsTheStore() {
    let store = MemoryStore(["notifications.phone.url": "https://ntfy.sh/secret-topic"])
    let load = withPhoneSecrets(loadConfig(toml: "[notifications.phone]\nafter = 1"), store: store)
    #expect(load.problems.isEmpty)
    #expect(load.config.phone.url == "https://ntfy.sh/secret-topic")
    #expect(load.config.phone.saved == [.url])
    #expect(load.config.phone.after == 60)
}

@Test func nothingInTheStoreLeavesPhonePushOff() {
    let load = withPhoneSecrets(loadConfig(toml: nil), store: MemoryStore())
    #expect(load.problems.isEmpty)
    #expect(load.config.phone == PhonePush())
    #expect(!load.config.phone.isOn)
}

@Test func aPartialPushoverPairStaysOff() {
    var load = loadConfig(toml: "[notifications.phone]\nformat = \"pushover\"")
    load = withPhoneSecrets(load, store: MemoryStore(["notifications.phone.pushover_user": "u1"]))
    #expect(load.config.phone.pushoverUser == "u1" && load.config.phone.pushoverToken == nil)
    #expect(load.config.phone.saved == [.pushover_user])
    #expect(!load.config.phone.isOn)
}

@Test func aBadAddressFromTheStoreStaysOffAndIsNotRepeated() {
    let load = withPhoneSecrets(loadConfig(toml: nil), store: MemoryStore(["notifications.phone.url": "ntfy.sh/secret-topic"]))
    #expect(load.config.phone.url == nil)
    #expect(load.config.phone.saved == [.url])  // Settings still says it is there, so it can be changed or removed
    #expect(load.problems == [phoneURLProblem("x")])
    #expect(!load.problems.joined().contains("secret-topic"))
}

@Test func anUnreadableStoreIsAProblem() {
    let store = MemoryStore(["notifications.phone.url": "https://ntfy.sh/t"])
    store.broken = true
    let load = withPhoneSecrets(loadConfig(toml: nil), store: store)
    #expect(load.config.phone.url == nil)
    #expect(load.problems.count == PhoneSecret.allCases.count)
}

@Test func secretsLeftInTheFileAreIgnoredAndReported() {
    let toml = """
    [notifications.phone]
    url = "https://ntfy.sh/secret-topic"
    pushover_user = "u123"
    pushover_token = ""
    after = 2
    """
    let load = withPhoneSecrets(loadConfig(toml: toml), store: MemoryStore())
    #expect(load.config.phone.url == nil && load.config.phone.pushoverUser == nil)
    #expect(load.problems == [PhoneSecret.url.inFileProblem, PhoneSecret.pushover_user.inFileProblem])
    #expect(load.problems.first == "notifications.phone.url is kept in the Keychain now. Set it in Settings → Notifications or with gzyms set notifications.phone.url.")
    #expect(!load.problems.joined().contains("secret-topic") && !load.problems.joined().contains("u123"))
    #expect(load.config.phone.after == 120)  // the rest of the table still counts
}

@Test func theStoreWinsOverTheFile() {
    let store = MemoryStore(["notifications.phone.url": "https://ntfy.sh/kept"])
    let load = withPhoneSecrets(loadConfig(toml: "[notifications.phone]\nurl = \"https://ntfy.sh/old\""), store: store)
    #expect(load.config.phone.url == "https://ntfy.sh/kept")
}

@Test func setAndUnsetGoToTheStore() {
    let store = MemoryStore()
    #expect(savePhoneSecret(.pushover_token, "  t1\n", store: store) == nil)
    #expect(store.values == ["notifications.phone.pushover_token": "t1"])
    #expect(savePhoneSecret(.pushover_token, nil, store: store) == nil)
    #expect(store.values.isEmpty)
    #expect(savePhoneSecret(.pushover_token, nil, store: store) == nil)  // removing what is not there is fine
}

@Test func aBadAddressIsNotSaved() {
    let store = MemoryStore(["notifications.phone.url": "https://ntfy.sh/old"])
    let problem = savePhoneSecret(.url, "ntfy.sh/secret-topic", store: store)
    #expect(problem == phoneURLProblem("x"))
    #expect(problem?.contains("secret-topic") == false)
    #expect(store.values == ["notifications.phone.url": "https://ntfy.sh/old"])
    #expect(savePhoneSecret(.url, "https://ntfy.sh/new", store: store) == nil)
    #expect(store.values["notifications.phone.url"] == "https://ntfy.sh/new")
}

@Test func aFailedStoreWriteSaysSo() {
    let store = MemoryStore()
    store.broken = true
    #expect(savePhoneSecret(.url, "https://ntfy.sh/t", store: store) == "notifications.phone.url: the Keychain said no (refused)")
}

@Test func theValueComesFromStdinUnlessTyped() {
    let key = "notifications.phone.url"
    #expect(secretInput([key], remove: false) == .stdin)
    #expect(secretInput([key, "-"], remove: false) == .stdin)
    #expect(secretInput([key, "https://ntfy.sh/t"], remove: false) == .inline("https://ntfy.sh/t"))
    #expect(secretInput([key, "a", "b"], remove: false) == nil)
    #expect(secretInput([key], remove: true) == .remove)
    #expect(secretInput([key, "x"], remove: true) == nil)
}

@Test func phoneSecretNamesTheirAccounts() {
    #expect(PhoneSecret.allCases.map(\.account) == ["notifications.phone.url", "notifications.phone.pushover_user", "notifications.phone.pushover_token"])
    #expect(PhoneSecret(account: "notifications.phone.pushover_user") == .pushover_user)
    #expect(PhoneSecret(account: "notifications.phone.after") == nil)
}
