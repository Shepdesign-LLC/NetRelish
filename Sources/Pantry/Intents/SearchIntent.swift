// SearchIntent.swift — "Search Your Pantry". The same full-text search as ⌘K, over what
// you've captured and sealed. It reads the Pantry on this Mac and hands the results to
// your Shortcut; nothing is sent anywhere (non-negotiable 5) and no model is involved.

import AppIntents
import Foundation

public struct SearchPantryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search Your Pantry"
    public static let description = IntentDescription("Finds pages you've captured or sealed in NetRelish, best match first.")
    public static let openAppWhenRun = false

    @Parameter(title: "Search for")
    public var query: String

    public init() {}
    public init(query: String) { self.query = query }

    public static var parameterSummary: some ParameterSummary {
        Summary("Search your Pantry for \(\.$query)")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[PantryItemEntity]> {
        .result(value: try PantryItemQuery.search(in: .shared, for: query))
    }
}
