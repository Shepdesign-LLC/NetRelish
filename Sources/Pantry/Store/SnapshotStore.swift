// SnapshotStore.swift — where sealed pages live: one `.webarchive` per Item, in
// Application Support beside the Pantry database, inside the sandbox container.
//
// `Item.snapshotPath` holds the name relative to this directory, never an absolute path:
// containers move between machines and OS upgrades, and an absolute path would rot.
//
// The name comes back out of the database, so it is checked before it is used. A snapshot
// is one file, directly inside this folder: a name that would step outside it (`../…`, a
// path with a folder in it, an absolute path) is refused for reading, writing and removing.

import Foundation

public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Why a snapshot was refused before any file was touched.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The store was given an address rather than a folder on this Mac.
        case notAFolderOnThisMac
        /// The name would reach outside the snapshot folder.
        case outsideTheStore(String)

        public var description: String {
            switch self {
            case .notAFolderOnThisMac: "Sealed pages are kept in a folder on this Mac, and this isn't one."
            case .outsideTheStore(let name): "\u{201C}\(name)\u{201D} isn't a sealed page in the snapshot folder."
            }
        }
    }

    /// Where a snapshot named `path` would be. For showing and for tests: reading, writing
    /// and removing check the name first (see `location(of:)`).
    public func url(for path: String) -> URL {
        directory.appendingPathComponent(path, isDirectory: false)
    }

    /// True when `name` is one file name and nothing else: no folders, no `..`, not empty.
    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\0")
    }

    /// The file `name` refers to, or a refusal if it isn't a file directly inside this folder.
    func location(of name: String) throws -> URL {
        guard directory.isFileURL else { throw Failure.notAFolderOnThisMac }
        guard SnapshotStore.isPlainFileName(name) else { throw Failure.outsideTheStore(name) }
        return url(for: name)
    }

    /// Writes (or overwrites) the archive for `itemId`. Returns the relative path to store.
    @discardableResult
    public func write(_ data: Data, for itemId: String) throws -> String {
        let path = "\(itemId).webarchive"
        let target = try location(of: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return path
    }

    /// Reads by file path, never by URL. `Data(contentsOf:)` reads whatever a URL points at,
    /// and given an https address that is a network request (non-negotiable 5). A path can
    /// only ever be a file.
    public func read(_ path: String) throws -> Data {
        try NSData(contentsOfFile: location(of: path).path, options: []) as Data
    }

    /// Removing something that isn't there is not an error — unsealing is allowed to be sloppy.
    public func remove(_ path: String) throws {
        let target = try location(of: path)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
