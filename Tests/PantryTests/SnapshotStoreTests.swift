import Foundation
import Testing
@testable import Pantry

@Suite("Snapshots") struct SnapshotStoreTests {

    private func store() -> SnapshotStore {
        SnapshotStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nr-snap-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("Writing a snapshot creates the directory and returns a path relative to it")
    func writeCreatesDirectory() throws {
        let snapshots = store()
        let path = try snapshots.write(Data("archive".utf8), for: "item-1")
        #expect(path == "item-1.webarchive")
        #expect(try snapshots.read(path) == Data("archive".utf8))
    }

    @Test("The stored path is relative, so moving the container doesn't break it")
    func pathIsRelative() throws {
        let snapshots = store()
        let path = try snapshots.write(Data("a".utf8), for: "item-2")
        #expect(!path.hasPrefix("/"))
        #expect(snapshots.url(for: path).path.hasSuffix("/item-2.webarchive"))
    }

    @Test("Sealing the same item twice overwrites rather than piling up")
    func overwrites() throws {
        let snapshots = store()
        _ = try snapshots.write(Data("first".utf8), for: "item-3")
        let path = try snapshots.write(Data("second".utf8), for: "item-3")
        #expect(try snapshots.read(path) == Data("second".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: snapshots.directory.path).count == 1)
    }

    @Test("Reading a snapshot that isn't there throws rather than returning empty data")
    func missingThrows() throws {
        let snapshots = store()
        #expect(throws: (any Error).self) { try snapshots.read("nope.webarchive") }
    }

    @Test("Removing a snapshot leaves nothing behind, and removing twice is fine")
    func remove() throws {
        let snapshots = store()
        let path = try snapshots.write(Data("a".utf8), for: "item-4")
        try snapshots.remove(path)
        try snapshots.remove(path)
        #expect(!FileManager.default.fileExists(atPath: snapshots.url(for: path).path))
    }
}
