import Foundation

/// The phone push keys that are secrets: anyone with an ntfy topic reads the pings, a webhook URL often carries a
/// token. They live in the login Keychain, never in config.toml.
public enum PhoneSecret: String, CaseIterable, Sendable {
    case url, pushover_user, pushover_token

    /// The Keychain account, and the dotted name `gzyms set` takes.
    public var account: String { "notifications.phone.\(rawValue)" }

    public init?(account: String) {
        guard let s = Self.allCases.first(where: { $0.account == account }) else { return nil }
        self = s
    }

    /// What config.toml says when it still holds the key. The value is ignored and never repeated.
    public var inFileProblem: String {
        "\(account) is kept in the Keychain now. Set it in Settings → Notifications or with gzyms set \(account)."
    }
}

/// Where the phone push secrets live: the login Keychain in the app, a dictionary in tests.
public protocol SecretStore {
    /// nil = not set. Throws when the store cannot be read.
    func get(_ account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    /// A key that is not there is not an error.
    func delete(_ account: String) throws
}

/// The problem for an address that is not http(s). Without the value: a mistyped one may still hold the topic.
public func phoneURLProblem(_ url: String) -> String? {
    if let scheme = URL(string: url)?.scheme?.lowercased(), ["http", "https"].contains(scheme) { return nil }
    return "notifications.phone.url: must start with https:// (an ntfy topic like https://ntfy.sh/your-topic), phone push stays off"
}

/// `load` with the phone push keys from `store`. A bad or unreadable one stays off and becomes a problem.
public func withPhoneSecrets(_ load: ConfigLoad, store: SecretStore) -> ConfigLoad {
    var load = load
    for s in PhoneSecret.allCases {
        let value: String?
        do { value = try store.get(s.account) } catch {
            load.problems.append("\(s.account): the Keychain could not be read (\(error)), phone push stays off")
            continue
        }
        guard let value, !value.isEmpty else { continue }
        load.config.phone.saved.insert(s)
        switch s {
        case .url:
            if let p = phoneURLProblem(value) { load.problems.append(p) } else { load.config.phone.url = value }
        case .pushover_user: load.config.phone.pushoverUser = value
        case .pushover_token: load.config.phone.pushoverToken = value
        }
    }
    return load
}

/// Where `gzyms set`/`unset` takes a phone push key's value from.
public enum SecretInput: Equatable, Sendable {
    /// Typed on the command line: works, but lands in shell history and `ps`.
    case inline(String)
    /// No value or `-`: a hidden prompt on a terminal, else one line from the pipe.
    case stdin
    case remove
}

/// `args` start with the key. nil = wrong usage.
public func secretInput(_ args: [String], remove: Bool) -> SecretInput? {
    if remove { return args.count == 1 ? .remove : nil }
    switch args.count {
    case 1: return .stdin
    case 2: return args[1] == "-" ? .stdin : .inline(args[1])
    default: return nil
    }
}

/// Saves one key, or with nil or blank removes it. Returns the problem when nothing was stored.
public func savePhoneSecret(_ s: PhoneSecret, _ value: String?, store: SecretStore) -> String? {
    let v = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if s == .url, !v.isEmpty, let p = phoneURLProblem(v) { return p }
    do {
        if v.isEmpty { try store.delete(s.account) } else { try store.set(v, for: s.account) }
        return nil
    } catch {
        return "\(s.account): the Keychain said no (\(error))"
    }
}
