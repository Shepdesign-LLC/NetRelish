import Foundation
import Testing
@testable import NetRelish
@testable import Pantry

/// Provenance on the Bench: a sealed page gets its fingerprint, and Export Proof writes a
/// folder that checks out without NetRelish.
@Suite("Provenance and Export Proof") @MainActor struct ProofTests {

    private func sealedPage(_ bench: Workbench) async throws -> Item {
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        let jarId = try #require(bench.activeJar?.id)
        bench.offscreenLoader = { url, _ in
            Workbench.OffscreenPage(
                archive: Data("WEBARCHIVE".utf8),
                extracted: Extraction.Result(title: "Pricing: Pro", excerpt: "", body: "Pro costs $29/mo."),
                url: url.absoluteString, title: "Pricing")
        }
        return try await bench.sealPage(at: URL(string: "https://example.com/pricing")!, into: jarId)
    }

    @Test("A sealed page is fingerprinted; with no authority in the tests, timestamps are off")
    func fingerprinted() async throws {
        let bench = Workbench(store: try PantryStore())
        let item = try await sealedPage(bench)
        await bench.stampWaitingNow()
        let provenance = try #require(bench.provenance(of: item))
        #expect(provenance.fingerprint == Provenance.fingerprint(of: Data("WEBARCHIVE".utf8)))
        #expect(!bench.timestampsOn)
        #expect(PanelText.timestamp(provenance, on: bench.timestampsOn) == "Not set up")
        #expect(PanelText.shortFingerprint(provenance.fingerprint).count == 17)
    }

    @Test("Export Proof writes the PDF, the saved copy byte for byte, and how to check them")
    func export() async throws {
        let bench = Workbench(store: try PantryStore())
        let item = try await sealedPage(bench)
        await bench.stampWaitingNow()
        let provenance = try #require(bench.provenance(of: item))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Proof \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        try ProofExport.write(item: item, provenance: provenance, archive: Data("WEBARCHIVE".utf8),
                              jarName: "Meridian", to: folder)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == [ProofText.howToCheckFile, ProofText.pdfFile, ProofText.archiveFile].sorted(),
                "no token without a timestamp")
        let copy = try Data(contentsOf: folder.appendingPathComponent(ProofText.archiveFile))
        #expect(Provenance.fingerprint(of: copy) == provenance.fingerprint)
        let pdf = try Data(contentsOf: folder.appendingPathComponent(ProofText.pdfFile))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        let howTo = try String(contentsOf: folder.appendingPathComponent(ProofText.howToCheckFile), encoding: .utf8)
        #expect(howTo.contains(provenance.fingerprint))
        #expect(howTo.contains("shasum -a 256 \"Saved copy.webarchive\""))
    }

    @Test("The proof's words: a safe name, the fingerprint in eights, the time with its zone")
    func words() throws {
        let item = Item(kind: .page, state: .sealed, title: "Plans: Pro/Team", url: "https://example.com/plans")
        #expect(ProofText.exportName(item) == "Proof – Plans- Pro-Team")
        #expect(ProofText.grouped("0123456789abcdef01") == "01234567 89abcdef 01")
        let utc = TimeZone(secondsFromGMT: 0)!
        #expect(ProofText.full(Date(timeIntervalSince1970: 0), in: utc).hasSuffix(" GMT")
                || ProofText.full(Date(timeIntervalSince1970: 0), in: utc).hasSuffix(" UTC"))
        let rows = ProofText.rows(item: item, provenance: Provenance(fingerprint: String(repeating: "a", count: 64)),
                                  jarName: "Clients")
        #expect(rows.map(\.label) == ["Page", "Address", "Jar", "Fingerprint (SHA-256 of the saved copy)", "Timestamp"])
        #expect(rows.last?.value == "None yet. The fingerprint above was worked out on this Mac.")
    }
}
