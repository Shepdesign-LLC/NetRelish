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

    @Test("A name that would step outside the snapshot folder is refused, and nothing is touched",
          arguments: ["../pantry.sqlite", "../../Library/Keychains/login.keychain-db", "/etc/hosts",
                      "sub/item.webarchive", "..", ".", ""])
    func refusesNamesOutsideTheFolder(name: String) throws {
        let snapshots = store()
        // Something beside the folder that a `../` name would reach.
        let parent = snapshots.directory.deletingLastPathComponent()
        let neighbor = parent.appendingPathComponent("nr-neighbor-\(UUID().uuidString)")
        try Data("keep".utf8).write(to: neighbor)
        defer { try? FileManager.default.removeItem(at: neighbor) }
        _ = try snapshots.write(Data("a".utf8), for: "item-5")

        #expect(throws: SnapshotStore.Failure.outsideTheStore(name)) { try snapshots.read(name) }
        #expect(throws: SnapshotStore.Failure.outsideTheStore(name)) { try snapshots.remove(name) }
        #expect(FileManager.default.contents(atPath: neighbor.path) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: snapshots.directory.path) == ["item-5.webarchive"])
    }

    @Test("An item id can't steer a seal into another folder")
    func refusesIdsOutsideTheFolder() throws {
        let snapshots = store()
        let parent = snapshots.directory.deletingLastPathComponent()
        let escaped = "nr-escaped-\(UUID().uuidString)"
        #expect(throws: SnapshotStore.Failure.outsideTheStore("../\(escaped).webarchive")) {
            try snapshots.write(Data("a".utf8), for: "../\(escaped)")
        }
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("\(escaped).webarchive").path))
        // Refused before the folder was even made.
        #expect(!FileManager.default.fileExists(atPath: snapshots.directory.path))
    }

    @Test("A snapshot store pointed at a web address reads nothing, rather than fetching it")
    func refusesARemoteDirectory() throws {
        let snapshots = SnapshotStore(directory: try #require(URL(string: "https://example.com/snapshots/")))
        #expect(throws: SnapshotStore.Failure.notAFolderOnThisMac) { try snapshots.read("item-6.webarchive") }
        #expect(throws: SnapshotStore.Failure.notAFolderOnThisMac) { try snapshots.write(Data("a".utf8), for: "item-6") }
        #expect(throws: SnapshotStore.Failure.notAFolderOnThisMac) { try snapshots.remove("item-6.webarchive") }
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
