// NetRelishApp.swift — the app. SwiftUI lifecycle, one main window, the Zest window
// (Window › Zest, ADR 0033), Help › Acknowledgments, and the DEBUG-only Design Kit as
// another Window scene (Window → Design Kit).

import AppIntents
import AppKit
import GRDB
import Pantry
import SwiftUI
import WebKit

@main
struct NetRelishApp: App {
    @State private var workbench: Workbench

    /// The main window's scene id, so the Zest window can open it again for a web link.
    static let mainWindowId = "main"

    /// The Share extension's inbox, except when this app is hosting the tests: they must never
    /// take what you've shared into the Pantry.
    private static var shareInbox: ShareInbox? {
        isHostingTests ? nil : ShareInbox()
    }

    /// Seal & Summarize's model: Apple's, on this Mac. None while hosting the tests, which
    /// bring their own stand-in.
    private static var summarizer: (any Summarizer)? {
        isHostingTests ? nil : OnDeviceSummarizer()
    }

    /// Pro provenance's timestamp authority, from the build settings (ADR 0022). None while
    /// hosting the tests: they never reach the network.
    private static var timestamps: (any TimestampAuthority)? {
        isHostingTests ? nil : TimestampService.configured
    }

    /// Whether Pro is unlocked (ADR 0023). The App Store build asks StoreKit; the Direct
    /// build reads the license key this Mac activated (ADR 0027), and stays unlocked only in a
    /// build with no license relay set up. Tests bring their own.
    private static var pro: ProStore {
        if isHostingTests { return ProStore(unlocked: true) }
        #if DIRECT_BUILD
        switch LicenseRelay.configured {
        case .notSet: return ProStore(unlocked: true)
        case .relay(let relay):
            return ProStore(licensedBy: relay, keptIn: LicenseKeychain.live, revocations: DefaultsRevocations.live)
        case .broken:
            return ProStore(licensedBy: NoLicenseRelay(), keptIn: LicenseKeychain.live,
                            revocations: DefaultsRevocations.live, misconfigured: true)
        }
        #else
        return .live()
        #endif
    }

    /// Only a debug build can be told it's hosting the tests. In a build that ships, an
    /// environment variable must not be able to unlock Pro or switch anything off.
    private static var isHostingTests: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    init() {
        let workbench = Workbench(inbox: NetRelishApp.shareInbox, summarizer: NetRelishApp.summarizer,
                                  timestamps: NetRelishApp.timestamps, pro: NetRelishApp.pro)
        _workbench = State(initialValue: workbench)
        // The Shortcuts that act on the app (Seal the page in front, Open a Jar) find it here.
        AppDependencyManager.shared.add(dependency: workbench)
        // "Open <jar> in NetRelish" needs the jar names: told at launch and on every change.
        workbench.onJarsChanged = { _ in NetRelishShortcuts.updateAppShortcutParameters() }
        #if DEBUG
        DesignKitSnapshot.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup("NetRelish", id: NetRelishApp.mainWindowId) {
            ContentView(workbench: workbench)
        }
        // The title strip is the top of the window (manifest v2.1 §10): no title bar of the
        // system's over it, only its three buttons.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            // Jars menu: ⌘1–9 switch jars (manifest §8 Shelf).
            CommandGroup(after: .appInfo) {
                Button("NetRelish Pro…") { workbench.showingPro = true }
            }
            // App Review 5.1.1(i): the privacy policy, one click away for everyone, not only
            // for someone who opens Pro (ADR 0032). It replaces the default Help item, which
            // has no help book to open. Acknowledgments sits beside it: the third-party notices (NOTICE).
            CommandGroup(replacing: .help) {
                Button(ProText.privacy) { NSWorkspace.shared.open(ProText.privacyURL) }
                AcknowledgmentsCommand()
            }
            // File › Print…: the Zest tool in front, Save as PDF included (Zest MD's PDF export).
            // A tool's window.print() has nothing to call in the app's web view. It stands down
            // while a jar's page is in front; a page that handles ⌘P itself still gets it first.
            CommandGroup(replacing: .printItem) {
                Button("Print…") { workbench.printZest?() }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(!workbench.zestInFront)
            }
            CommandMenu("Jars") {
                ForEach(Array(workbench.jars.prefix(9).enumerated()), id: \.element.id) { index, jar in
                    Button(jar.name) { workbench.activate(index: index) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Divider()
                ForEach(SmartJar.allCases) { smart in
                    Button(smart.name) { workbench.activate(smart) }
                        .keyboardShortcut(KeyEquivalent(Character(String(smart.number))), modifiers: SmartJar.shortcutModifiers)
                }
                Divider()
                Button("Edit Jar…") { workbench.requestEditActiveJar() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(workbench.activeJar == nil)
            }
            CommandMenu("Bench") {
                Button("Command Palette…") { workbench.showPalette = true }.keyboardShortcut("k", modifiers: .command)
                Button(workbench.showPanel ? "Hide Panel" : "Show Panel") { workbench.showPanel.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                // pageInFront is nil while the Zest window is in front: these act on a tab, and
                // the page in front is then a tool (ADR 0015).
                Button("Capture This Page") { workbench.captureActivePage() }.keyboardShortcut("d", modifiers: .command)
                    .disabled(workbench.pageInFront == nil)
                Button("Seal") { Task { await workbench.sealActiveTab() } }.keyboardShortcut("s", modifiers: .command)
                    .disabled(workbench.pageInFront == nil)
                Button(workbench.isReading ? "Back to the Page" : "Reader View") { Task { await workbench.toggleReader() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(workbench.pageInFront == nil)
                Divider()
                Button("Fill from Me") { workbench.fillFromMe() }.keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(workbench.pageInFront == nil || workbench.isReading)
            }
            CommandMenu("Tab") {
                Button("New Tab") { workbench.newTab() }.keyboardShortcut("t", modifiers: .command)
                Button(workbench.comparison != nil ? "Close Comparison"
                       : workbench.savedCopy != nil ? "Close Saved Copy" : "Close Tab") { workbench.closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(workbench.zestInFront
                              || (workbench.benchTab == nil && workbench.savedCopy == nil && workbench.comparison == nil))
                Button(workbench.pageInFront?.isPinned == true ? "Unpin Tab" : "Pin Tab") { workbench.togglePinActiveTab() }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(workbench.pageInFront == nil)
            }
        }

        // Settings → Me: the card, in the Keychain (ADR 0006).
        Settings {
            MeSettingsView(vault: workbench.vault)
        }

        // Window › Zest: the four free Zest tools, offline (ADR 0015, ADR 0033). A `Window`
        // scene gets its Window-menu item from SwiftUI. No keyboard shortcut: ⌘⇧Z is Redo.
        Window("Zest", id: "zest") {
            ZestWindow(workbench: workbench)
        }
        .defaultSize(width: 1180, height: 820)

        // Help › Acknowledgments opens it; it keeps no item of its own in the Window menu.
        Window("Acknowledgments", id: Acknowledgments.windowId) {
            AcknowledgmentsView()
        }
        .defaultSize(width: 680, height: 720)
        .commandsRemoved()

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

/// The main window (manifest v2.1 §10, ADR 0035): a title strip across the top, with the
/// window's buttons, the cog mark and the tabs; under it the Shelf, then the Bench column (the
/// address row over the Bench), with the Panel sliding in over the column's trailing edge; a
/// bottom bar with Brine across the whole width. ⌘K floats over the Bench column, and the Seal
/// motion plays in one overlay over the whole window. The window's title still carries the
/// active jar's name, for the Window menu and Mission Control; the jar's chip shows it in the
/// window.
struct ContentView: View {
    @Bindable var workbench: Workbench
    /// This window's web views. Each window keeps its own.
    @State private var webViews = BenchWebViews()
    /// How much of the Bench column the open Panel takes. It changes once, after the Panel has
    /// slid in, so a real page reflows once and never per frame (manifest v2.1 §9).
    @State private var panelInset: CGFloat
    @Environment(\.nrReduceMotion) private var reduceMotion

    init(workbench: Workbench) {
        self.workbench = workbench
        _panelInset = State(initialValue: workbench.showPanel ? NRSpace.inspectorW : 0)
    }

    /// The page in front in this window, if the Bench is showing one.
    private var webInFront: JarWebView? { workbench.benchTab.map { webViews.view(for: $0) } }

    /// The Panel's way in: a 200ms slide on ease-out; under Reduce Motion, a cross-fade of the
    /// same length (manifest v2.1 §9: slides become cross-fades).
    private var panelTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing)
    }

    /// ⌘K's box fades in and grows from 0.98 to its size; under Reduce Motion it only fades.
    private var paletteBoxTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.98, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleRow(workbench: workbench)
            HStack(spacing: 0) {
                ShelfView(workbench: workbench)
                benchColumn
            }
            BottomBar(workbench: workbench)
        }
        // Seal's one overlay, over everything, once (ADR 0035). Inside the safe-area change, so
        // it covers the title strip too and reads every anchor in the window's own space.
        .sealOverlay(workbench)
        .ignoresSafeArea(.container, edges: .top)   // the title strip sits where the title bar was
        .frame(minWidth: NRShell.windowMinW, minHeight: NRShell.windowMinH)
        .background(NRColor.bg)
        .navigationTitle(workbench.activeSmartJar?.name ?? workbench.activeJar?.name ?? "NetRelish")
        .navigationSubtitle("\(workbench.itemCount) \(workbench.itemCount == 1 ? "item" : "items")")
        .task { await workbench.observe() }
        .task { await workbench.runSweep() }
        // The Panel takes its room only once it has slid in; closing gives the room back at once.
        .task(id: workbench.showPanel) {
            guard workbench.showPanel else {
                panelInset = 0
                return
            }
            guard panelInset != NRSpace.inspectorW else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(NRMotion.base))
            }
            guard !Task.isCancelled, workbench.showPanel else { return }
            panelInset = NRSpace.inspectorW
        }
        // Registers this window as the main one, so a web link from Zest brings it forward.
        // A view leaving its window says nil, which is ignored: the reference is weak.
        .background(WindowReader { window in if let window { workbench.mainWindow = window } })
        .sheet(isPresented: $workbench.showMeOnboarding) {
            MeOnboardingSheet(vault: workbench.vault) { workbench.fillFromMe() }
        }
        .sheet(isPresented: $workbench.showingPro) {
            ProView(pro: workbench.pro) { workbench.showingPro = false }
        }
    }

    /// The address row over the Bench. The Panel slides in over its trailing edge, and ⌘K
    /// floats over all of it on a flat scrim.
    private var benchColumn: some View {
        VStack(spacing: 0) {
            SearchRow(workbench: workbench, web: webInFront)
            BenchView(workbench: workbench, webViews: webViews)
        }
        .padding(.trailing, panelInset)
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                if workbench.showPanel {
                    PanelView(workbench: workbench)
                        .transition(panelTransition)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(NRMotion.animation(duration: NRMotion.base), value: workbench.showPanel)
        }
        .overlay {
            ZStack(alignment: .top) {
                if workbench.showPalette {
                    NRColor.canvas.opacity(0.72)
                        .contentShape(Rectangle())
                        .onTapGesture { workbench.showPalette = false }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    PaletteView(workbench: workbench)
                        .padding(.top, 56)
                        .transition(paletteBoxTransition)
                }
            }
            // It fades even under Reduce Motion; only the box's scale stays put.
            .animation(NRMotion.animation(duration: NRMotion.base), value: workbench.showPalette)
        }
        // ⌘K is an overlay, not a sheet, so nothing hands the keyboard back when it closes:
        // give it to the page in front, as a dismissed sheet did.
        .onChange(of: workbench.showPalette) { _, open in
            guard !open, let web = webInFront else { return }
            _ = web.webView.window?.makeFirstResponder(web.webView)
        }
    }
}

extension SmartJar {
    /// The one place the smart jars' modifier keys live: the Jars menu, the Shelf's tooltips
    /// and ⌘K all read these, so they can't disagree.
    /// ⌃⌘, not the manifest's original ⌘⇧: ⌘⇧3 and ⌘⇧4 are macOS's screenshot keys (ADR 0014).
    static let shortcutModifiers: EventModifiers = [.control, .command]
    static let shortcutSymbols = "⌃⌘"
    var shortcutLabel: String { "\(Self.shortcutSymbols)\(number)" }
}
