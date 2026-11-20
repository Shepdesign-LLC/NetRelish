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
        #if DEBUG
        // The UI test's launch (-NRUITestFixture, Tests/NetRelishUITests): a throwaway Pantry and
        // defaults, two jars and a page served inside the app. Nothing below is set up for it,
        // so Shortcuts and Siri never reach the real Pantry from a test run. Not in Release.
        if let fixture = UITestFixture.makeWorkbench() {
            _workbench = State(initialValue: fixture)
            return
        }
        #endif
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
            // From outside: ContentView reads nrReduceMotion itself, and a modifier inside its
            // body wouldn't reach that read. Its sheets (Me, Pro) inherit it.
            ContentView(workbench: workbench)
                .nrSystemAccessibility()
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
                // Every jar, so the tenth and later can be reached from the menu bar too; the
                // first nine keep ⌘1–9.
                ForEach(Array(workbench.jars.enumerated()), id: \.element.id) { index, jar in
                    if index < 9 {
                        Button(jar.name) { showJar(jar) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    } else {
                        Button(jar.name) { showJar(jar) }
                    }
                }
                Divider()
                ForEach(SmartJar.allCases) { smart in
                    Button(smart.name) {
                        workbench.activate(smart)
                        NRAnnounce.post(CommandSpeech.smartJar(smart, count: workbench.count(of: smart)))
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(smart.number))), modifiers: SmartJar.shortcutModifiers)
                }
                Divider()
                // The board's other ways in are the cog mark and the jar's chip, both small
                // buttons; this one a keyboard or VoiceOver user can find by name.
                Button("Show Board") {
                    workbench.showBoard()
                    if let jar = workbench.activeJar { NRAnnounce.post(CommandSpeech.board(jarName: jar.name)) }
                }
                .disabled(workbench.activeJar == nil)
                Button("Edit Jar…") { workbench.requestEditActiveJar() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(workbench.activeJar == nil)
                // Sliding a jar along the Shelf needs a pointer, and its Move Up and Move Down
                // live in a right-click menu the keyboard can't open: these move the jar you're in.
                Divider()
                Button("Move Jar Up") { moveActiveJar(by: -1) }
                    .disabled(!canMoveActiveJar(by: -1))
                Button("Move Jar Down") { moveActiveJar(by: 1) }
                    .disabled(!canMoveActiveJar(by: 1))
            }
            CommandMenu("Bench") {
                Button("Open Location…") { workbench.focusAddress() }.keyboardShortcut("l", modifiers: .command)
                    .disabled(workbench.zestInFront)
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
                // The tab's right-click menu and a drag onto a jar both need a pointer; this is
                // the way into a jar from the keyboard and from VoiceOver.
                Menu("Move Tab to Jar") {
                    ForEach(workbench.jars.filter { $0.id != workbench.pageInFront?.jarId }) { jar in
                        Button(jar.name) { moveTabInFront(to: jar) }
                    }
                }
                .disabled(workbench.pageInFront == nil || workbench.jars.count < 2)
                // Dragging a tab along the strip needs a pointer, and the tab's Move Left and
                // Move Right live in a right-click menu the keyboard can't open: the same moves.
                Button("Move Tab Left") { moveTabInFront(by: -1) }
                    .disabled(neighborOfTabInFront(by: -1) == nil)
                Button("Move Tab Right") { moveTabInFront(by: 1) }
                    .disabled(neighborOfTabInFront(by: 1) == nil)
                Divider()
                // The tab chips take keyboard focus only with Keyboard navigation on, and ⌘K
                // lists open tabs only once something is typed: these step through the strip
                // from anywhere (Safari's keys). From the board they're also the way back into
                // the strip (`TabCycle`); a smart jar has no strip, and Zest's tools aren't tabs.
                Button("Show Next Tab") { showNeighborTab(1) }
                    .keyboardShortcut(.tab, modifiers: .control)
                    .disabled(!canCycleTabs)
                Button("Show Previous Tab") { showNeighborTab(-1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                    .disabled(!canCycleTabs)
            }
        }

        // Settings → Me: the card, in the Keychain (ADR 0006).
        Settings {
            MeSettingsView(vault: workbench.vault)
                .nrSystemAccessibility()
        }

        // Window › Zest: the four free Zest tools, offline (ADR 0015, ADR 0033). A `Window`
        // scene gets its Window-menu item from SwiftUI. No keyboard shortcut: ⌘⇧Z is Redo.
        Window("Zest", id: "zest") {
            ZestWindow(workbench: workbench)
                .nrSystemAccessibility()
        }
        .defaultSize(width: 1180, height: 820)

        // Help › Acknowledgments opens it; it keeps no item of its own in the Window menu.
        Window("Acknowledgments", id: Acknowledgments.windowId) {
            AcknowledgmentsView()
                .nrSystemAccessibility()
        }
        .defaultSize(width: 680, height: 720)
        .commandsRemoved()

        #if DEBUG
        // A secondary `Window` scene gets its item in the Window menu from SwiftUI. No
        // nrSystemAccessibility here: the kit sets nrReduceMotion itself, with its own toggle.
        Window("Design Kit", id: "design-kit") {
            DesignKitView()
        }
        .defaultSize(width: 1180, height: 820)
        .keyboardShortcut("d", modifiers: [.command, .option])
        #endif
    }

    /// A jar from the Jars menu. ⌘1–9 change the Bench while VoiceOver stays where it was
    /// (often in the page), so it's told where it is now.
    private func showJar(_ jar: Jar) {
        workbench.activate(jar)
        NRAnnounce.post(CommandSpeech.jar(jar.name, openTabs: workbench.tabCount(in: jar)))
    }

    /// Tab › Move Tab to Jar. The drop's path, so the move, the jar's rules and its fill
    /// (once, after the write) are the same as dragging the tab onto the jar.
    private func moveTabInFront(to jar: Jar) {
        guard let tab = workbench.pageInFront, tab.jarId != jar.id else { return }
        if workbench.drop([DragPayload.tab(tab.id).string], onJar: jar) {
            NRAnnounce.post(CommandSpeech.moved(to: jar.name), priority: .high)
        }
    }

    /// Tab › Move Tab Left and Move Tab Right: the tab one place along, as the tab's own menu
    /// (`TabStrip.neighbor(of:in:offset:)`); nil at that end of the strip.
    private func neighborOfTabInFront(by offset: Int) -> String? {
        guard let tab = workbench.pageInFront else { return nil }
        return TabStrip.neighbor(of: tab.id, in: workbench.tabs.map(\.id), offset: offset)
    }

    /// The tab's own Move Left and Move Right: dropped onto its neighbor, which puts it at the
    /// neighbor's old place, then where it is now said, in the strip's words.
    private func moveTabInFront(by offset: Int) {
        let order = workbench.tabs.map(\.id)
        guard let tab = workbench.pageInFront,
              let target = TabStrip.neighbor(of: tab.id, in: order, offset: offset),
              let index = order.firstIndex(of: target) else { return }
        workbench.moveTab(tab.id, onto: target)
        NRAnnounce.post(TabStrip.movedAnnouncement(position: index + 1, count: order.count))
    }

    /// Jars › Move Jar Up and Move Jar Down: off at that end of the Shelf.
    private func canMoveActiveJar(by step: Int) -> Bool {
        guard let jar = workbench.activeJar,
              let from = workbench.jars.firstIndex(where: { $0.id == jar.id }) else { return false }
        return workbench.jars.indices.contains(from + step)
    }

    /// The jar's own Move Up and Move Down, then where it is now, as the Shelf says it.
    private func moveActiveJar(by step: Int) {
        guard let jar = workbench.activeJar, canMoveActiveJar(by: step),
              let from = workbench.jars.firstIndex(where: { $0.id == jar.id }) else { return }
        workbench.moveJar(jar, by: step)
        let now = workbench.jars.firstIndex(where: { $0.id == jar.id }) ?? from + step
        NRAnnounce.post(JarTile.moveLine(jarName: jar.name, index: now, count: workbench.jars.count))
    }

    /// Show Next Tab and Show Previous Tab need a tab to land on, and a jar's strip in front.
    private var canCycleTabs: Bool { !workbench.zestInFront && !workbench.tabs.isEmpty }

    /// Show Next Tab and Show Previous Tab: the neighbor in the strip, wrapping at the ends,
    /// and its name and place said, since VoiceOver's cursor doesn't follow the strip.
    private func showNeighborTab(_ step: Int) {
        let tabs = workbench.tabs
        guard let id = TabCycle.neighbor(of: workbench.activeTab?.id, in: tabs.map(\.id), step: step),
              let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        workbench.activateTab(tab)
        NRAnnounce.post(CommandSpeech.tab(name: TabStrip.spokenLabel(of: tab), position: index + 1, count: tabs.count))
    }
}

/// Which tab Show Next Tab and Show Previous Tab land on: the neighbor `step` places away,
/// wrapping round the strip. With no tab in front, the first one.
enum TabCycle {
    static func neighbor(of activeId: String?, in ids: [String], step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let index = activeId.flatMap({ ids.firstIndex(of: $0) }) else { return ids.first }
        let count = ids.count
        return ids[((index + step) % count + count) % count]
    }
}

/// What VoiceOver hears after a menu command changes the Bench without moving its cursor.
/// User-facing copy (docs/voice): the jar's name first, then what's there. On the main actor:
/// it reads the Shelf's and the strip's own lines, which are a view's.
@MainActor enum CommandSpeech {
    /// A jar from ⌘1–9 or the Jars menu: "Client site, 3 tabs".
    static func jar(_ name: String, openTabs: Int) -> String {
        switch openTabs {
        case 0: "\(name), no open tabs"
        case 1: "\(name), 1 tab"
        default: "\(name), \(openTabs) tabs"
        }
    }

    /// A smart jar from ⌃⌘1–4, in the Shelf's words for what it holds: Sinking soon holds
    /// open tabs, the others items. "Brine, 2 items", "Sinking soon, 1 tab".
    static func smartJar(_ smart: SmartJar, count: Int) -> String {
        let held: String
        switch smart {
        case .sinking: held = count == 0 ? "none" : count == 1 ? "1 tab" : "\(count) tabs"
        case .brine, .today, .sealed: held = count == 0 ? "empty" : count == 1 ? "1 item" : "\(count) items"
        }
        return "\(smart.name), \(held)"
    }

    /// Jars › Show Board, as a jar tile on the Shelf says it: "Client site board".
    static func board(jarName: String) -> String { ShelfView.boardLine(jarName: jarName) }

    /// Tab › Move Tab to Jar, as a drop on a jar says it: "Moved to Client site".
    static func moved(to jarName: String) -> String { JarTile.movedLine(jarName: jarName) }

    /// Show Next Tab or Show Previous Tab: the tab's name as the strip says it
    /// (`TabStrip.spokenLabel(of:)`: its title, else its site, else "New Tab"), and where it is
    /// in the strip, in the strip's words. "Pricing, 2 of 5".
    static func tab(name: String, position: Int, count: Int) -> String {
        "\(name), \(position) of \(count)"
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
    /// Who had the keyboard when ⌘K opened, so closing it can hand it back.
    @State private var paletteReturn = PaletteReturn()
    @Environment(\.nrReduceMotion) private var reduceMotion
    /// Under Reduce Transparency ⌘K's scrim is solid: the page doesn't show through it.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The Workbench is every window's: only the key window says what it changed.
    @Environment(\.controlActiveState) private var activeState

    init(workbench: Workbench) {
        self.workbench = workbench
        _panelInset = State(initialValue: workbench.showPanel ? NRSpace.inspectorW : 0)
    }

    /// What VoiceOver hears when the Panel opens or closes.
    static func panelLine(shown: Bool) -> String { shown ? "Panel shown" : "Panel hidden" }

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
        // The tree keeps the window's reading order: tabs, Shelf, address row, Bench, Panel,
        // bottom bar. While ⌘K is open everything behind it leaves the accessibility tree, so
        // VoiceOver's cursor stays in the palette and Escape still reaches it. The rows carry
        // their own focus sections and names; the Bench gets its here.
        VStack(spacing: 0) {
            TitleRow(workbench: workbench)
                .accessibilityHidden(workbench.showPalette)
            HStack(spacing: 0) {
                ShelfView(workbench: workbench)
                    .accessibilityHidden(workbench.showPalette)
                benchColumn
            }
            BottomBar(workbench: workbench)
                .accessibilityHidden(workbench.showPalette)
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
        // ⌘⌥I from the menu changes nothing VoiceOver is on, so the Panel says it came or went.
        // Only a change: the Panel that is open at launch says nothing.
        .onChange(of: workbench.showPanel) { _, shown in
            guard activeState == .key else { return }
            NRAnnounce.post(ContentView.panelLine(shown: shown))
        }
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
            // The page or the board: one stop for Tab and the arrow keys under Full Keyboard
            // Access, and one named group, so VoiceOver can say where the Bench starts.
            BenchView(workbench: workbench, webViews: webViews)
                .focusSection()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Bench")
        }
        // Before the overlays, so ⌘K itself stays in the tree.
        .accessibilityHidden(workbench.showPalette)
        .padding(.trailing, panelInset)
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                if workbench.showPanel {
                    PanelView(workbench: workbench)
                        .accessibilityHidden(workbench.showPalette)
                        .transition(panelTransition)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(NRMotion.animation(duration: NRMotion.base), value: workbench.showPanel)
        }
        .overlay {
            ZStack(alignment: .top) {
                if workbench.showPalette {
                    NRColor.canvas.opacity(reduceTransparency ? 1 : 0.72)
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
        // Whoever had the keyboard when it opened (a tab, Reader view, a saved copy) gets it
        // back if it is still in the window; otherwise the page in front does.
        .onChange(of: workbench.showPalette) { _, open in
            if open {
                paletteReturn.responder = (webInFront?.webView.window ?? NSApp.keyWindow)?.firstResponder
                return
            }
            let previous = paletteReturn.responder as? NSView
            paletteReturn.responder = nil
            if let previous, let window = previous.window, !previous.isHiddenOrHasHiddenAncestor {
                _ = window.makeFirstResponder(previous)
            } else if let web = webInFront {
                _ = web.webView.window?.makeFirstResponder(web.webView)
            } else {
                // A smart jar or the board came forward, and whoever had the keyboard has gone:
                // the first control in the window takes it, a turn later once the new view is
                // in, so the keyboard and VoiceOver aren't left nowhere.
                let window = previous?.window ?? NSApp.keyWindow
                Task { @MainActor in window?.selectNextKeyView(nil) }
            }
        }
    }
}

/// Holds the responder ⌘K took the keyboard from, weakly: a view that has gone stays gone.
@MainActor final class PaletteReturn {
    weak var responder: NSResponder?
}

extension SmartJar {
    /// The one place the smart jars' modifier keys live: the Jars menu, the Shelf's tooltips
    /// and ⌘K all read these, so they can't disagree.
    /// ⌃⌘, not the manifest's original ⌘⇧: ⌘⇧3 and ⌘⇧4 are macOS's screenshot keys (ADR 0014).
    static let shortcutModifiers: EventModifiers = [.control, .command]
    static let shortcutSymbols = "⌃⌘"
    var shortcutLabel: String { "\(Self.shortcutSymbols)\(number)" }
}
