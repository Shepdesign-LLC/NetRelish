import Foundation
import Security
import Testing
@testable import NetRelish

/// Runs inside the app (the sandbox Keychain is keyed to the app's signing identity).
/// Uses its own service name so it never touches the real Me card.
@Suite("VaultStore", .serialized) struct VaultStoreTests {

    private func fresh() throws -> VaultStore {
        let store = VaultStore(service: "com.shepdesign.netrelish.vault.tests.\(UUID().uuidString)")
        return store
    }

    private var sample: Identity {
        var me = Identity()
        me.givenName = "Ryan"; me.email = "ryan@example.com"; me.city = "Denver"
        return me
    }

    @Test("Nothing stored reads back as nil")
    func emptyIsNil() throws {
        let store = try fresh()
        #expect(try store.identity(for: nil) == nil)
        #expect(try store.identity(for: "jar-1") == nil)
    }

    @Test("Save, read, overwrite, remove — the Me card")
    func roundTrip() throws {
        let store = try fresh()
        defer { try? store.removeAll() }
        try store.save(sample, for: nil)
        #expect(try store.identity(for: nil) == sample)
        var changed = sample; changed.city = "Boulder"
        try store.save(changed, for: nil)
        #expect(try store.identity(for: nil) == changed)
        try store.remove(for: nil)
        #expect(try store.identity(for: nil) == nil)
    }

    @Test("A jar's own card wins; without one the jar falls back to Me")
    func jarOverride() throws {
        let store = try fresh()
        defer { try? store.removeAll() }
        try store.save(sample, for: nil)
        #expect(try store.identity(for: "jar-1") == sample)
        #expect(try store.hasOverride(for: "jar-1") == false)
        var work = sample; work.email = "ryan@work.example"
        try store.save(work, for: "jar-1")
        #expect(try store.hasOverride(for: "jar-1"))
        #expect(try store.identity(for: "jar-1") == work)
        #expect(try store.identity(for: "jar-2") == sample)
        try store.remove(for: "jar-1")
        #expect(try store.identity(for: "jar-1") == sample)
    }

    @Test("Items are never marked synchronizable (non-negotiable 5)")
    func neverSyncs() throws {
        let store = try fresh()
        defer { try? store.removeAll() }
        try store.save(sample, for: nil)
        let attrs = try store.attributes(for: nil)
        #expect(attrs[kSecAttrSynchronizable as String] as? Bool != true)
        #expect(attrs[kSecAttrService as String] as? String == store.service)
    }
}
