// JarProfile.swift — every jar is a profile (non-negotiable 6). One WKWebsiteDataStore
// per jar, keyed by the jar's id, so cookies and sessions never cross jars.
//
// WKWebsiteDataStore(forIdentifier:) wants a UUID. Jar ids are strings — UUIDs for jars
// the user creates, readable names for the seeded ones ("read-later"). A non-UUID id is
// mapped to a stable UUID (v5 over a fixed namespace), so the same jar always opens the
// same store across launches.

import CryptoKit
import Foundation
import WebKit

public enum JarProfile {
    /// The namespace every non-UUID jar id is hashed under. Never change it: it is what
    /// keeps "read-later" pointing at the same cookies forever.
    static let namespace = UUID(uuidString: "6B0F5C2A-9F3E-4F0E-8C3B-2A7D1E5F9C11")!

    /// The data-store identifier for a jar.
    public static func storeIdentifier(for jarId: String) -> UUID {
        if let direct = UUID(uuidString: jarId) { return direct }
        return uuidV5(namespace: namespace, name: jarId)
    }

    /// The jar's persistent website data store. Cookies, local storage, caches — all scoped.
    @MainActor
    public static func dataStore(for jarId: String) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: storeIdentifier(for: jarId))
    }

    /// Removes a jar's store entirely — every cookie and session gone. Called when a jar is deleted.
    @MainActor
    public static func removeDataStore(for jarId: String) async throws {
        try await WKWebsiteDataStore.remove(forIdentifier: storeIdentifier(for: jarId))
    }

    /// RFC 4122 §4.3 name-based UUID (SHA-1).
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: Array(name.utf8))
        var hash = Array(Insecure.SHA1.hash(data: bytes)).prefix(16)
        hash[6] = (hash[6] & 0x0F) | 0x50   // version 5
        hash[8] = (hash[8] & 0x3F) | 0x80   // RFC 4122 variant
        let h = Array(hash)
        return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
    }
}
