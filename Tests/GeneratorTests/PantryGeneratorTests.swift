import Foundation
import Testing

@Suite("Pantry generator") struct PantryGeneratorTests {

    @Test("Sources/Pantry/Models matches a fresh run of gen-pantry.swift")
    func noDrift() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gen-pantry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (code, _, err) = try runScript("scripts/gen-pantry.swift", ["design/NetRelish.json", tmp.path])
        #expect(code == 0, "generator failed: \(err)")
        let committed = repoRoot.appendingPathComponent("Sources/Pantry/Models")
        let fresh = Set(try FileManager.default.contentsOfDirectory(atPath: tmp.path))
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: committed.path).filter { $0.hasSuffix(".swift") })
        #expect(fresh == existing, "file set differs: fresh \(fresh) vs committed \(existing)")
        for name in fresh.intersection(existing) {
            let a = try String(contentsOf: tmp.appendingPathComponent(name), encoding: .utf8)
            let b = try String(contentsOf: committed.appendingPathComponent(name), encoding: .utf8)
            #expect(a == b, "\(name) is stale — run scripts/gen-pantry.swift")
        }
    }

    @Test("A method in the diagram without a behavior body is rejected")
    func missingBodyRejected() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gen-pantry-bad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Strip one behavior from a copy of the bundle.
        let url = repoRoot.appendingPathComponent("design/NetRelish.json")
        var bundle = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var behaviors = bundle["behaviors"] as! [String: [String: Any]]
        let victim = behaviors.first { ($0.value["state"] as? String) == "run" }!.key
        behaviors.removeValue(forKey: victim)
        bundle["behaviors"] = behaviors
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: bundle).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        let (code, _, err) = try runScript("scripts/gen-pantry.swift", [broken.path, tmp.path])
        #expect(code != 0)
        #expect(err.contains("Recipe.run"))
    }
}
