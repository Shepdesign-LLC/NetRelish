// NetRelishApp.swift — the app. SwiftUI lifecycle, one main window, and the
// DEBUG-only Design Kit as a second Window scene (Window → Design Kit).

import GRDB
import Pantry
import SwiftUI

@main
struct NetRelishApp: App {
    @State private var workbench = Workbench()

    init() {
        #if DEBUG
        DesignKitSnapshot.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup("NetRelish") {
            ContentView(workbench: workbench)
        }
        .defaultSize(width: 1180, height: 820)
        .commands {
            // Jars menu: ⌘1–9 switch jars (manifest §8 Shelf).
            CommandMenu("Jars") {
                ForEach(Array(workbench.jars.prefix(9).enumerated()), id: \.element.id) { index, jar in
                    Button(jar.name) { workbench.activate(index: index) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Divider()
                Button("Brine") { workbench.activateBrine() }.keyboardShortcut("1", modifiers: [.command, .shift])
                Divider()
                Button("Edit Jar…") { workbench.requestEditActiveJar() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(workbench.activeJar == nil)
            }
            CommandMenu("Bench") {
                Button("Fill from Me") { workbench.fillFromMe() }.keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(workbench.activeTab == nil)
            }
            CommandMenu("Tab") {
                Button("New Tab") { workbench.newTab() }.keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") { workbench.closeActiveTab() }.keyboardShortcut("w", modifiers: .command)
                    .disabled(workbench.activeTab == nil)
                Button(workbench.activeTab?.isPinned == true ? "Unpin Tab" : "Pin Tab") { workbench.togglePinActiveTab() }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(workbench.activeTab == nil)
            }
        }

        // Settings → Me: the card, in the Keychain (ADR 0006).
        Settings {
            MeSettingsView(vault: workbench.vault)
        }

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

/// The main window: Shelf on the leading edge, Bench filling the rest (manifest §10).
/// The title carries the active jar's name; the subtitle, the Pantry's item count.
struct ContentView: View {
    @Bindable var workbench: Workbench

    var body: some View {
        HStack(spacing: 0) {
            ShelfView(workbench: workbench)
            BenchView(workbench: workbench)
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(NRColor.bg)
        .navigationTitle(workbench.showingBrine ? "Brine" : (workbench.activeJar?.name ?? "NetRelish"))
        .navigationSubtitle("\(workbench.itemCount) \(workbench.itemCount == 1 ? "item" : "items")")
        .task { await workbench.observe() }
        .task { await workbench.runSweep() }
        .sheet(isPresented: $workbench.showMeOnboarding) {
            MeOnboardingSheet(vault: workbench.vault) { workbench.fillFromMe() }
        }
    }
}
