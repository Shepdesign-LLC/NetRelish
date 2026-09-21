// SealIntent.swift — "Seal in NetRelish". Seals the captured item for a URL.

import AppIntents
import Foundation
import GRDB

public struct SealIntent: AppIntent {
    public static let title: LocalizedStringResource = "Seal in NetRelish"
    public static let description = IntentDescription("Seals the item captured from a URL. Sealing is one-way.")
    public static let openAppWhenRun = false

    @Parameter(title: "URL")
    public var url: URL

    public init() {}
    public init(url: URL) { self.url = url }

    public static var parameterSummary: some ParameterSummary {
        Summary("Seal \(\.$url) in NetRelish")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let store = PantryStore.shared
        let link = url.absoluteString
        let sealed = try store.write { db -> Bool in
            guard let item = try Item.filter(Item.Columns.url == link).order(Item.Columns.updatedAt.desc).fetchOne(db) else {
                return false
            }
            let root = try store.root(db)
            try root.seal(db, item: item)
            return true
        }
        return .result(value: sealed)
    }
}
