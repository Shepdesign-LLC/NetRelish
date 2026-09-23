// SnapshotStore.swift — where sealed pages live: one `.webarchive` per Item, in
// Application Support beside the Pantry database, inside the sandbox container.
//
// `Item.snapshotPath` holds the name relative to this directory, never an absolute path:
// containers move between machines and OS upgrades, and an absolute path would rot.

import Foundation

public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for path: String) -> URL {
        directory.appendingPathComponent(path, isDirectory: false)
    }

    /// Writes (or overwrites) the archive for `itemId`. Returns the relative path to store.
    @discardableResult
    public func write(_ data: Data, for itemId: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = "\(itemId).webarchive"
        try data.write(to: url(for: path), options: .atomic)
        return path
    }

    public func read(_ path: String) throws -> Data {
        try Data(contentsOf: url(for: path))
    }

    /// Removing something that isn't there is not an error — unsealing is allowed to be sloppy.
    public func remove(_ path: String) throws {
        let target = url(for: path)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
