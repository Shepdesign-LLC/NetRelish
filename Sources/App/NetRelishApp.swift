// NetRelishApp.swift — the app. SwiftUI lifecycle, one main window, and the
// DEBUG-only Design Kit as a second Window scene (Window → Design Kit).

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
struct ContentView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 880, minHeight: 560)
            .background(NRColor.bg)
    }
}
