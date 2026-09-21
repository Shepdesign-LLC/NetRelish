import Foundation
import Testing
@testable import Pantry

@Suite("Jar profiles") struct JarProfileTests {

    @Test("A UUID jar id is its own store identifier")
    func uuidPassthrough() {
        let id = UUID().uuidString
        #expect(JarProfile.storeIdentifier(for: id) == UUID(uuidString: id))
    }

    @Test("A named jar id maps to the same UUID every time, and different names differ")
    func stableMapping() {
        let a1 = JarProfile.storeIdentifier(for: "read-later")
        let a2 = JarProfile.storeIdentifier(for: "read-later")
        let b = JarProfile.storeIdentifier(for: "reference")
        #expect(a1 == a2)
        #expect(a1 != b)
        // Pinned: if this ever changes, every seeded jar loses its cookies.
        #expect(a1.uuidString == "14839E53-D25E-5222-B62D-421B8204F8EB")
    }

    @Test("v5 UUIDs carry the version and variant bits")
    func rfc4122() {
        let u = JarProfile.uuidV5(namespace: JarProfile.namespace, name: "anything")
        #expect(u.uuidString.dropFirst(14).first == "5")
        #expect(["8", "9", "A", "B"].contains(String(u.uuidString.dropFirst(19).first!)))
    }
}
