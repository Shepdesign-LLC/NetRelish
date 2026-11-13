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

    /// The one website data store that is never a jar's: the Zest window's (ADR 0015, ADR 0033).
    /// Reserved here, beside the jars' derivation, so no jar id can ever map to it. It is a
    /// version-4 UUID and every derived id below is version 5, so the hash can't land on it;
    /// a jar whose id is this UUID's own text is moved off it by `storeIdentifier(for:)`.
    /// Never change it: it is what keeps the tools' saved work across launches.
    public static let zestStoreIdentifier = UUID(uuidString: "3E8A1C57-0D2B-4F6A-9B1E-7C54A2F0D9E3")!

    /// The namespace for that one move, used for nothing else. A separate namespace, so the
    /// moved jar's store can't equal the store of a jar whose id is some other string: under
    /// `namespace`, a jar id spelled "jar:" + the UUID would hash to the same place.
    static let zestRemapNamespace = UUID(uuidString: "8951E795-7C66-4762-B2A9-6784696AC708")!

    /// The data-store identifier for a jar. Never `zestStoreIdentifier`.
    public static func storeIdentifier(for jarId: String) -> UUID {
        if let direct = UUID(uuidString: jarId) {
            // A jar id that spells Zest's identifier gets a derived one instead, so its
            // cookies can't land in Zest's store or Zest's storage in the jar (non-negotiable 6).
            // Derived from the canonical spelling, so either case of the UUID opens one store.
            guard direct == zestStoreIdentifier else { return direct }
            return uuidV5(namespace: zestRemapNamespace, name: direct.uuidString)
        }
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
