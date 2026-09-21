// CaptureIntent.swift — "Capture in NetRelish". Shortcuts and Siri call the same
// NetRelish.capture the app does (non-negotiable 7: every Recipe is an App Intent;
// capture and seal are the first two).

import AppIntents
import Foundation

public struct CaptureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture in NetRelish"
    public static let description = IntentDescription("Saves a web page into Brine, the unsorted part of your Pantry.")
    public static let openAppWhenRun = false

    @Parameter(title: "URL")
    public var url: URL

    public init() {}
    public init(url: URL) { self.url = url }

    public static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$url) in NetRelish")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = PantryStore.shared
        let link = url.absoluteString
        let title = try store.write { db in
            let root = try store.root(db)
            return try root.capture(db, url: link).title
        }
        return .result(value: title)
    }
}
