// ShareInbox.swift — how the Share extension hands pages to the app. The extension can't
// open the Pantry (it's in the app's own container), so it leaves each shared page in an
// App Group both can read, and the app takes them into Brine the next time it looks.
//
// Foundation only: the Share extension compiles this one file too (project.yml), and must
// not pull in GRDB. Nothing here touches the network (non-negotiable 5); the hand-off is a
// preferences file on this Mac.

import Foundation

/// A page someone shared from another app, waiting for the app to put it in Brine.
public struct SharedPage: Codable, Equatable, Sendable {
    public var url: String
    public var title: String
    public var sharedAt: Date

    public init(url: String, title: String, sharedAt: Date = Date()) {
        self.url = url
        self.title = title
        self.sharedAt = sharedAt
    }
}

public struct ShareInbox: @unchecked Sendable {   // UserDefaults is thread-safe
    /// Team-ID-prefixed, the form macOS accepts without a provisioning profile.
    public static let appGroup = "D9QDJ44773.com.shepdesign.netrelish"
    static let keyPrefix = "share."

    private let defaults: UserDefaults

    /// The shared inbox, or nil if the App Group can't be opened.
    public init?(suiteName: String = ShareInbox.appGroup) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    /// One key per page, so the extension adding and the app taking never overwrite each
    /// other's work: the app removes exactly the keys it read.
    public func add(_ page: SharedPage) {
        guard let data = try? JSONEncoder().encode(page) else { return }
        defaults.set(data, forKey: Self.keyPrefix + UUID().uuidString)
    }

    /// Hands everything waiting, oldest first, to `receive`, then removes exactly those
    /// entries. If `receive` throws, they stay for next time, so a failed write loses nothing.
    /// An entry that can't be read is removed either way: it would never read.
    public func take(_ receive: ([SharedPage]) throws -> Void) rethrows {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Self.keyPrefix) }
        var pages: [(key: String, page: SharedPage)] = []
        for key in keys {
            if let data = defaults.data(forKey: key), let page = try? JSONDecoder().decode(SharedPage.self, from: data) {
                pages.append((key, page))
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        guard !pages.isEmpty else { return }
        try receive(pages.sorted { $0.page.sharedAt < $1.page.sharedAt }.map(\.page))
        for entry in pages { defaults.removeObject(forKey: entry.key) }
    }
}
