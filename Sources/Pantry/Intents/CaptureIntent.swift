// CaptureIntent.swift — "Capture in NetRelish". Shortcuts and Siri put a page in Brine the
// way ⌘D does, with "Shortcuts" as its source (non-negotiable 7: every Recipe is an App
// Intent; capture and seal are the first two).

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
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ShortcutError.notAWebPage
        }
        let title = try store.write { db in
            try store.capture(db, url: link, source: .shortcut).title
        }
        return .result(value: title)
    }
}
