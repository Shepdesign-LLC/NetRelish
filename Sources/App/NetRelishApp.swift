// NetRelishApp.swift — the app. SwiftUI lifecycle, one main window, and the
// DEBUG-only Design Kit as a second Window scene (Window → Design Kit).

import GRDB
import Pantry
import SwiftUI

@main
struct NetRelishApp: App {
    init() {
        #if DEBUG
        DesignKitSnapshot.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup("NetRelish") {
            ContentView()
        }
        .defaultSize(width: 1180, height: 820)

        #if DEBUG
        // A secondary `Window` scene gets its item in the Window menu from SwiftUI.
        Window("Design Kit", id: "design-kit") {
            DesignKitView()
        }
        .defaultSize(width: 1180, height: 820)
        .keyboardShortcut("d", modifiers: [.command, .option])
        #endif
    }
}

/// The main window. Empty for now — P1 puts the Shelf, Bench, and Inspector here.
/// The title carries the Pantry's item count, live, so a capture from Shortcuts shows up.
struct ContentView: View {
    @State private var itemCount: Int?

    var body: some View {
        Color.clear
            .frame(minWidth: 880, minHeight: 560)
            .background(NRColor.bg)
            .navigationTitle(title)
            .task { await observeItemCount() }
    }

    private var title: String {
        guard let itemCount else { return "NetRelish" }
        return "NetRelish — \(itemCount) \(itemCount == 1 ? "item" : "items")"
    }

    private func observeItemCount() async {
        let observation = ValueObservation.tracking { db in try Item.fetchCount(db) }
        do {
            for try await count in observation.values(in: PantryStore.shared.dbQueue) {
                itemCount = count
            }
        } catch {
            itemCount = nil
        }
    }
}
