import Foundation
import GzymsCore
import Security

/// The phone push secrets in the login Keychain: one generic password per key, service dev.gzyms, account
/// `notifications.phone.<key>`. The only place that calls the Security framework.
struct KeychainStore: SecretStore {
    static let service = "dev.gzyms"

    struct Failure: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)" }
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
    }

    func get(_ account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess, let data = out as? Data else { throw Failure(status: s) }
        return String(decoding: data, as: UTF8.self)
    }

    func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let s = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard s == errSecItemNotFound else {
            if s != errSecSuccess { throw Failure(status: s) }
            return
        }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let a = SecItemAdd(q as CFDictionary, nil)
        if a != errSecSuccess { throw Failure(status: a) }
    }

    func delete(_ account: String) throws {
        let s = SecItemDelete(query(account) as CFDictionary)
        if s != errSecSuccess && s != errSecItemNotFound { throw Failure(status: s) }
    }
}
