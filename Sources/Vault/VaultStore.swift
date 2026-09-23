// VaultStore.swift — the Me card in the Keychain. One item per card: account "me" for the
// default, "jar:<id>" for a jar's override. Never synchronizable — the OS enforces
// non-negotiable 5 here, not a promise in a README.
//
// This is the login (file-based) Keychain, ACL'd to the app's code signature. The
// data-protection Keychain needs a keychain-access-groups entitlement and therefore a
// provisioning profile, which CI (CODE_SIGNING_ALLOWED=NO) cannot have; ADR 0006 defers
// that switch to the App Store submission phase.

import Foundation
import Security

struct VaultError: Error, CustomStringConvertible {
    let status: OSStatus
    var description: String { (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)" }
}

struct VaultStore: Sendable {
    static let live = VaultStore(service: "com.shepdesign.netrelish.vault")

    let service: String

    /// The jar's own card if it has one, else the Me card. Nil when neither is set.
    func identity(for jarId: String?) throws -> Identity? {
        if let jarId, let own = try read(account: Self.account(for: jarId)) { return own }
        return try read(account: Self.account(for: nil))
    }

    func hasOverride(for jarId: String) throws -> Bool {
        try read(account: Self.account(for: jarId)) != nil
    }

    func save(_ identity: Identity, for jarId: String?) throws {
        let account = Self.account(for: jarId)
        let data = try Identity.encode(identity)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound:
            var add = query(account)
            add[kSecValueData as String] = data
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw VaultError(status: added) }
        default: throw VaultError(status: status)
        }
    }

    func remove(for jarId: String?) throws {
        let status = SecItemDelete(query(Self.account(for: jarId)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }

    /// Every card under this service. Tests use it to clean up; the app never calls it.
    func removeAll() throws {
        let status = SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }

    /// The stored item's attributes, for tests that assert on accessibility and sync.
    func attributes(for jarId: String?) throws -> [String: Any] {
        var q = query(Self.account(for: jarId))
        q[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let attrs = out as? [String: Any] else { throw VaultError(status: status) }
        return attrs
    }

    // MARK: - Private

    static func account(for jarId: String?) -> String { jarId.map { "jar:\($0)" } ?? "me" }

    private var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func query(_ account: String) -> [String: Any] {
        var q = base
        q[kSecAttrAccount as String] = account
        return q
    }

    private func read(account: String) throws -> Identity? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { return nil }
            return try Identity.decode(data)
        case errSecItemNotFound: return nil
        default: throw VaultError(status: status)
        }
    }
}
