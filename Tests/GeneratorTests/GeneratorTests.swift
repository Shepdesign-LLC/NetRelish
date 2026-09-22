import Foundation
import Testing

/// The generators are the contract between /design and Sources/UI.
/// These tests pin: (1) committed output is exactly what the generator emits today,
/// (2) the generator refuses CSS that would make "one property → one static" untrue.
@Suite("Generators") struct GeneratorTests {

    @Test("Tokens.swift matches a fresh run of gen-tokens.swift")
    func tokensNoDrift() throws {
        let (code, out, err) = try runScript("scripts/gen-tokens.swift", ["design/tokens.css"])
        #expect(code == 0, "generator failed: \(err)")
        let committed = try String(contentsOf: repoRoot.appendingPathComponent("Sources/UI/Tokens.swift"), encoding: .utf8)
        #expect(out == committed, "Sources/UI/Tokens.swift is stale — run scripts/gen-tokens.swift")
    }

    @Test("Symbols.swift matches a fresh run of gen-symbols.swift")
    func symbolsNoDrift() throws {
        let (code, out, err) = try runScript("scripts/gen-symbols.swift", ["design/symbols.svg", "design/logo.svg", "design/logo-cog.svg"])
        #expect(code == 0, "generator failed: \(err)")
        let committed = try String(contentsOf: repoRoot.appendingPathComponent("Sources/UI/Symbols.swift"), encoding: .utf8)
        #expect(out == committed, "Sources/UI/Symbols.swift is stale — run scripts/gen-symbols.swift")
    }

    @Test("Dark blocks that disagree are rejected")
    func darkMismatchRejected() throws {
        let (code, _, err) = try runScript("scripts/gen-tokens.swift", ["Tests/GeneratorTests/Fixtures/bad-dark-mismatch.css"])
        #expect(code != 0)
        #expect(err.contains("--nr-bg"))
    }

    @Test("A property with no enum to live in is rejected")
    func unknownPropertyRejected() throws {
        let (code, _, err) = try runScript("scripts/gen-tokens.swift", ["Tests/GeneratorTests/Fixtures/bad-unknown-property.css"])
        #expect(code != 0)
        #expect(err.contains("--mystery-thing"))
    }

    @Test("A dark-only property with no light value is rejected")
    func darkOrphanRejected() throws {
        let (code, _, err) = try runScript("scripts/gen-tokens.swift", ["Tests/GeneratorTests/Fixtures/bad-dark-orphan.css"])
        #expect(code != 0)
        #expect(err.contains("--nr-ghost"))
    }
}
