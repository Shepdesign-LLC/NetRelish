// ShortcutsIntents.swift — the Shortcuts that need the app itself: Seal, which freezes a page
// in a web view, and Open a Jar, which shows one. Capture and Search live in the Pantry
// (Sources/Pantry/Intents). All four are listed in NetRelishShortcuts, so they appear in
// Shortcuts, Spotlight and Siri without setup (non-negotiable 7).
//
// Seal reads only the page you named, in the jar's own profile, and keeps it on this Mac.
// No model sees it (non-negotiable 4) and nothing is sent anywhere (non-negotiable 5).

import AppIntents
import Foundation
import Pantry

struct SealPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Seal in NetRelish"
    static let description = IntentDescription(
        "Seals a web page into a jar: a saved copy of the page as it is now, its text searchable, and the jar's Recipe run. With no link, seals the page in front in NetRelish."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Link", description: "Leave empty to seal the page in front in NetRelish.")
    var url: URL?

    @Parameter(title: "Jar", description: "Where the page goes. If empty, the jar it was last kept in, or the active jar.")
    var jar: JarEntity?

    @Dependency private var workbench: Workbench

    static var parameterSummary: some ParameterSummary {
        Summary("Seal \(\.$url) into \(\.$jar)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let url else { return .result(value: try await workbench.sealFrontPage()) }
        return .result(value: try await workbench.sealPage(at: url, into: jar?.id).title)
    }
}

struct OpenJarIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Jar"
    static let description = IntentDescription("Brings NetRelish forward, showing one of your jars.")
    static let openAppWhenRun = true

    @Parameter(title: "Jar")
    var jar: JarEntity

    @Dependency private var workbench: Workbench

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$jar) in NetRelish")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard workbench.show(jarId: jar.id) else { throw ShortcutError.jarGone }
        return .result()
    }
}

/// The Shortcuts NetRelish offers without setup, and what to say to Siri.
struct NetRelishShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SealPageIntent(),
            phrases: ["Seal this page in \(.applicationName)", "Seal in \(.applicationName)"],
            shortTitle: "Seal",
            systemImageName: "seal"
        )
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["Capture in \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "tray.and.arrow.down"
        )
        AppShortcut(
            intent: OpenJarIntent(),
            phrases: ["Open \(\.$jar) in \(.applicationName)", "Show \(\.$jar) in \(.applicationName)"],
            shortTitle: "Open a Jar",
            systemImageName: "square.stack"
        )
        AppShortcut(
            intent: SearchPantryIntent(),
            phrases: ["Search my Pantry in \(.applicationName)", "Search \(.applicationName)"],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }
}
