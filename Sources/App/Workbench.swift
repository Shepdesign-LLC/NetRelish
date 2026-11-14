// Workbench.swift — the app's live state: the jars on the Shelf, the active jar, its tabs,
// the active tab, Brine, and the sweep that sinks idle tabs. Observed by everything.

import AppKit
import Foundation
import GRDB
import Observation
import OSLog
import Pantry

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "workbench")

/// SwiftUI has its own `Tab`; in this app the word means the Pantry's.
typealias Tab = Pantry.Tab

/// What a drag inside the window carries: a tab from the strip, or a row from Brine. It rides
/// as a plain string, so a drop reads it back with `init?(_:)`, and anything else dragged in
/// (a link, some text from another app) reads as nil and is left alone.
enum DragPayload: Equatable {
    case tab(String)
    case brine(String)

    private static let prefix = "netrelish-drag"

    var string: String {
        switch self {
        case .tab(let id): "\(Self.prefix):tab:\(id)"
        case .brine(let id): "\(Self.prefix):brine:\(id)"
        }
    }

    init?(_ string: String) {
        let parts = string.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == Self.prefix, !parts[2].isEmpty else { return nil }
        switch parts[1] {
        case "tab": self = .tab(parts[2])
        case "brine": self = .brine(parts[2])
        default: return nil
        }
    }
}

/// The Shelf's smart jars, ⌃⌘1–4. None is a row: each is a query that fills itself, and
/// nothing is ever moved into one (non-negotiable 2: Brine is a query, not a place).
enum SmartJar: String, CaseIterable, Identifiable {
    case brine, today, sealed, sinking

    /// The id the Workbench holds in `activeJarId` while this smart jar is showing.
    var id: String { "smart:\(rawValue)" }
    static let brineId = SmartJar.brine.id

    init?(id: String?) {
        guard let id, id.hasPrefix("smart:") else { return nil }
        self.init(rawValue: String(id.dropFirst("smart:".count)))
    }

    var name: String {
        switch self {
        case .brine: "Brine"
        case .today: "Today"
        case .sealed: "Sealed"
        case .sinking: "Sinking soon"
        }
    }

    /// The digit in its ⌘⇧ shortcut.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// Under its name in ⌘K.
    var paletteSubtitle: String {
        switch self {
        case .brine: "Everything unsorted"
        case .today: "What came in today"
        case .sealed: "Every sealed page"
        case .sinking: "Tabs about to sink"
        }
    }

    /// One line at the top of the smart jar, saying what fills it.
    var blurb: String {
        switch self {
        case .brine: "Tabs sink here when their jar's shelf life runs out. Nothing is lost."
        case .today: "Everything that came into your Pantry since midnight, from every jar."
        case .sealed: "Every page you've sealed, newest first."
        case .sinking: "Open tabs near the end of their jar's shelf life. Open one and it starts fresh."
        }
    }

    var emptyMessage: String {
        switch self {
        case .brine: "Nothing has sunk yet."
        case .today: "Nothing came in today."
        case .sealed: "Nothing sealed yet. Press ⌘S on a page you'll need again."
        case .sinking: "Nothing is about to sink."
        }
    }
}

@MainActor
@Observable
final class Workbench {
    let store: PantryStore
    private(set) var jars: [Jar] = []
    private(set) var activeJarId: String?
    private(set) var tabs: [Tab] = []          // the active jar's tabs, in order
    private(set) var activeTabId: String?
    private(set) var brine: [Item] = []
    /// The Today and Sealed smart jars, kept current by `observe()`.
    private(set) var todayItems: [Item] = []
    private(set) var sealedItems: [Item] = []
    /// Every open tab in every jar. Sinking soon is worked out from these and the clock.
    private(set) var allTabs: [Tab] = []
    private(set) var itemCount = 0
    /// Ticks once a second so the strip can fade tabs in their last 10%.
    private(set) var now = Date()

    /// Set by the Jars menu; the Shelf presents the sheet.
    var jarToEdit: Jar?
    func requestEditActiveJar() { jarToEdit = activeJar }

    /// Called before a tab sinks so the Bench can hand over the web view's interaction state.
    var interactionStateProvider: ((Tab) -> Data?)?
    /// Called with the ids of tabs that no longer exist (closed, sealed or sunk), so the Bench
    /// lets go of their web views. Switching jars or showing a smart jar never calls it: those
    /// tabs are still open, and their pages stay live.
    var onTabsGone: (([String]) -> Void)?

    /// The icon the user gave a tab (right-click a tab), as an SF Symbol name, by tab id.
    /// Kept in UserDefaults until `Tab` has a glyph of its own in the model (ADR 0028).
    private(set) var tabGlyphs: [String: String] = [:]
    private let defaults: UserDefaults
    private static let tabGlyphsKey = "tab.glyphs"

    // MARK: Vault (the Me card)

    let vault: VaultStore
    /// Set by the Bench: fills `identity` into the tab's web view, returns the count.
    var formFiller: ((Tab, Identity) async throws -> Int)?
    /// One line in the address bar for a couple of seconds after ⌘⇧F.
    private(set) var fillStatus: String?
    /// ⌘⇧F with an empty card opens onboarding instead of filling.
    var showMeOnboarding = false

    var activeJar: Jar? { jars.first { $0.id == activeJarId } }
    /// The smart jar the Bench is showing, if one is.
    var activeSmartJar: SmartJar? { SmartJar(id: activeJarId) }
    var showingSmartJar: Bool { activeSmartJar != nil }
    var activeTab: Tab? { tabs.first { $0.id == activeTabId } }
    /// The tab the Bench is showing, or nil when a smart jar or a saved copy covers it.
    /// Capture, Seal, Fill and Pin act on this, never on a tab the user can't see.
    var benchTab: Tab? { savedCopy == nil && comparison == nil && !showingSmartJar ? activeTab : nil }

    // MARK: Zest in front (ADR 0015, ADR 0033)

    /// True while the Zest window is the main window. The commands that act on the page in
    /// front (Seal, Capture, Reader, Fill from Me, Pin, Close Tab) stand down: the page in
    /// front is a tool, and ⌘S in ZestMail must never seal a page in the main window.
    ///
    /// Decided by main, not key: a tool's color picker (NSColorPanel, or WebKit's popover), an
    /// alert or a save panel takes key while Zest stays main, because panels, popovers and
    /// sheets never become main. Going by key would switch the gating off under them.
    private(set) var zestInFront = false
    /// The Zest window, once it has been shown. Weak: closing it lets it go.
    @ObservationIgnored weak var zestWindow: NSWindow?
    /// The main window (the Shelf and the Bench), registered by `ContentView`, so a web link
    /// from a tool brings that window forward and never Settings or the Design Kit. Weak.
    @ObservationIgnored weak var mainWindow: NSWindow?
    /// The tab the page commands act on: the Bench's, unless Zest is in front.
    var pageInFront: Tab? { zestInFront ? nil : benchTab }

    func setZestInFront(_ inFront: Bool) {
        if zestInFront != inFront { zestInFront = inFront }
    }

    /// Whether `window` is the Zest window, or a sheet attached to it.
    static func isZest(_ window: NSWindow?, zest: NSWindow?) -> Bool {
        guard let window, let zest else { return false }
        return window === zest || window.sheetParent === zest
    }

    /// A window became main, or stopped being main. A window becoming main decides; one
    /// resigning only matters if it was Zest's (the window closing, or the app going to the
    /// background), and the next window to become main decides again. A panel (the color
    /// panel, an open or save panel) never becomes main; if one is ever said to, it changes
    /// nothing.
    func mainWindowChanged(_ window: NSWindow?, becameMain: Bool) {
        // Until a Zest window exists, Zest can't be in front, and nothing here may change that.
        guard zestWindow != nil else { return }
        if becameMain, let window, window is NSPanel { return }
        let isZest = Self.isZest(window, zest: zestWindow)
        if becameMain { setZestInFront(isZest) } else if isZest { setZestInFront(false) }
    }

    private func watchMainWindow() {
        for name in [NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            let becameMain = name == NSWindow.didBecomeMainNotification
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { self?.mainWindowChanged(window, becameMain: becameMain) }
            }
        }
    }

    /// Today, re-checked against the clock, so the list empties at midnight on its own.
    var today: [Item] {
        let start = Calendar.current.startOfDay(for: now)
        return todayItems.filter { $0.createdAt >= start }
    }

    /// Open tabs in the last tenth of their shelf life, soonest to sink first. The clock
    /// ticks every second, so this moves without a database change.
    var sinkingSoon: [Tab] { ShelfLife.sinkingSoon(allTabs, jars: jars, now: now) }

    /// What a smart jar holds right now, for its count on the Shelf.
    func count(of smart: SmartJar) -> Int {
        switch smart {
        case .brine: brine.count
        case .today: today.count
        case .sealed: sealedItems.count
        case .sinking: sinkingSoon.count
        }
    }

    /// Where the Share extension leaves pages. The app passes the App Group's; tests pass
    /// their own or none, so they never take what you shared.
    let inbox: ShareInbox?

    /// Writes summaries for Seal & Summarize. The app passes the on-device one; tests pass a
    /// stand-in or none, so no test ever waits on a model.
    let summaries: SummaryWorker?

    /// Fingerprints every sealed page, and timestamps it when this build has a timestamp
    /// authority and Pro is unlocked (ADR 0022).
    let provenanceWorker: ProvenanceWorker

    /// Whether Pro is unlocked, and buying it (ADR 0023). The app passes StoreKit's answer in
    /// the App Store build and a fixed yes in the Direct build; tests default to unlocked.
    let pro: ProStore

    /// The Pro sheet: what Pro adds, the prices, buying and restoring. Opens from the app
    /// menu, or by using a Pro feature while it's locked.
    var showingPro = false

    private let timestampAuthority: (any TimestampAuthority)?

    /// Whether sealed pages get timestamps, not only fingerprints.
    var timestampsOn: Bool { pro.isUnlocked && timestampAuthority != nil }

    init(store: PantryStore = .shared, vault: VaultStore = .live, inbox: ShareInbox? = nil,
         summarizer: (any Summarizer)? = nil, timestamps: (any TimestampAuthority)? = nil,
         pro: ProStore = ProStore(unlocked: true), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.vault = vault
        self.inbox = inbox
        self.pro = pro
        self.summaries = summarizer.map { SummaryWorker(store: store, summarizer: $0) }
        self.timestampAuthority = timestamps
        let authority = pro.isUnlocked ? timestamps : nil
        self.provenanceWorker = ProvenanceWorker(store: store, authority: authority)
        tabGlyphs = defaults.dictionary(forKey: Self.tabGlyphsKey) as? [String: String] ?? [:]
        load()
        if inbox != nil { watchInbox() }
        if summaries != nil {
            // Coming back to NetRelish (say, after turning Apple Intelligence on) tries again.
            _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.summarizeWaiting() }
            }
        }
        if timestamps != nil {
            // Coming back to NetRelish (say, after the Mac was offline) tries the stamps
            // again. Registered whenever this build can stamp at all — Pro may be locked now
            // and bought later — and gated inside on Pro being unlocked then.
            _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.timestampsOn == true { self?.stampWaiting() } }
            }
        }
        summarizeWaiting()   // anything sealed just before the last quit
        stampWaiting()
        pro.onChange = { [weak self] in self?.proChanged() }
        watchMainWindow()
    }

    /// The last Pro flip being applied, so two quick flips land in order.
    private var proFlip: Task<Void, Never>?

    /// Pro was bought, restored, refunded or lapsed: stamping follows, from the next sweep.
    private func proChanged() {
        let authority = pro.isUnlocked ? timestampAuthority : nil
        let previous = proFlip
        proFlip = Task { @MainActor [weak self] in
            await previous?.value
            await self?.provenanceWorker.set(authority: authority)
            await self?.stampWaitingNow()
        }
    }

    // MARK: Seal & Summarize

    /// Ticks when summaries land, so the Panel reads them again.
    private(set) var summaryRevision = 0

    /// Starts writing summaries for sealed pages that are waiting for one. Seal never waits
    /// on this: the page is sealed and the tab closed first.
    func summarizeWaiting() {
        guard summaries != nil else { return }
        Task { @MainActor [weak self] in await self?.summarizeWaitingNow() }
    }

    /// The same, awaited. Tests call this to know the summaries are written.
    func summarizeWaitingNow() async {
        guard let summaries else { return }
        let changed = await summaries.sweep()
        if !changed.isEmpty { summaryRevision += 1 }
        retryLaterIfStillWaiting()
    }

    /// Whether a minute's retry is already set.
    private var summaryRetryScheduled = false

    /// A page still says "Summarizing" (the model is downloading, or busy): look again in a
    /// minute, so the line stays true while you watch. Pages set aside because Apple
    /// Intelligence is off wait for you to come back to the app instead.
    private func retryLaterIfStillWaiting() {
        guard !summaryRetryScheduled else { return }
        let stillWaiting = (try? store.read { db in
            try store.awaitingSummary(db).contains { item in
                if case .unavailable? = item.storedSummary { return false }
                return true
            }
        }) ?? false
        guard stillWaiting else { return }
        summaryRetryScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.summaryRetryScheduled = false
            self?.summarizeWaiting()
        }
    }

    /// Where a sealed page's summary stands, for the Panel. Nil when none is coming.
    func summary(of item: Item) -> SummaryState? {
        try? store.read { db in try store.summaryState(db, of: item.id) }
    }

    // MARK: Provenance (Pro)

    /// Ticks when provenance lands, so the Panel reads it again.
    private(set) var provenanceRevision = 0

    /// Starts fingerprinting and timestamping sealed pages that are waiting. Seal never waits.
    func stampWaiting() {
        Task { @MainActor [weak self] in await self?.stampWaitingNow() }
    }

    /// The same, awaited. Tests call this to know the provenance is written.
    func stampWaitingNow() async {
        let changed = await provenanceWorker.sweep()
        if !changed.isEmpty { provenanceRevision += 1 }
    }

    /// The provenance stored on a sealed page, read fresh.
    func provenance(of item: Item) -> Provenance? {
        (try? store.read { db in try Item.fetchOne(db, key: item.id) })?.provenance
    }

    /// Asks where to save the proof of a sealed page, then saves it there: a one-page PDF,
    /// the saved copy itself and the timestamp token (ADR 0022).
    func exportProof(_ item: Item) {
        pro.settle()   // a year that ran out since launch locks here, without a call
        guard pro.isUnlocked else { showingPro = true; return }
        guard let provenance = provenance(of: item), let path = item.snapshotPath else {
            report("This page’s fingerprint isn’t ready yet")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Proof"
        panel.prompt = "Export"
        panel.nameFieldStringValue = ProofText.exportName(item)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            let archive = try store.snapshots.read(path)
            guard Provenance.fingerprint(of: archive) == provenance.fingerprint else {
                // Never expected: the saved copy is frozen. Say so rather than export a proof
                // that wouldn't check out.
                report("The saved copy no longer matches its fingerprint")
                return
            }
            let jarName = jars.first { $0.id == item.jarId }?.name
            try ProofExport.write(item: item, provenance: provenance, archive: archive, jarName: jarName, to: target)
            report("Proof exported")
        } catch {
            log.error("export proof: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t export the proof")
        }
    }

    // MARK: The Share extension

    /// Watches the inbox for as long as the app runs, whether or not a window is open: at
    /// launch, every 5 seconds, and whenever the app comes forward. A page shared from Safari
    /// is in Brine within seconds, and at once when you switch to NetRelish.
    private func watchInbox() {
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.receiveShared() }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                self?.receiveShared()
                try? await Task.sleep(for: .seconds(5))
                if self == nil { return }
            }
        }
    }

    /// Takes in whatever was shared from another app's Share menu since the last look, into
    /// Brine.
    func receiveShared() {
        guard let inbox else { return }
        do {
            var received: [Item] = []
            try inbox.take { pages in
                received = try store.write { db in try store.receive(db, pages) }
            }
            guard !received.isEmpty else { return }
            refreshSmartJars()
            report(received.count == 1 ? "Shared into Brine" : "\(received.count) pages shared into Brine")
        } catch {
            log.error("share: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t take in a shared page. It will be tried again.")
        }
    }

    // MARK: Fill from Me

    /// Bench → Fill from Me (⌘⇧F). The jar's own card wins over Me. Never runs on its own,
    /// and never into a page Reader view is covering: you'd be filling fields you can't see.
    func fillFromMe() {
        guard !zestInFront else { return }
        if isReading { report("Go back to the page to fill a form"); return }
        guard let tab = pageInFront, let filler = formFiller else { return }
        Task { @MainActor in
            do {
                guard let identity = try vault.identity(for: tab.jarId), !identity.isEmpty else {
                    showMeOnboarding = true
                    return
                }
                let count = try await filler(tab, identity)
                let source = try tab.jarId.map { try vault.hasOverride(for: $0) } == true ? "\(activeJar?.name ?? "this jar")’s card" : "Me"
                report(count == 0 ? "Nothing to fill on this page" : "Filled \(count) \(count == 1 ? "field" : "fields") from \(source)")
            } catch {
                log.error("fill: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
                report("Couldn’t fill this form")
            }
        }
    }

    private func report(_ text: String) {
        fillStatus = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if fillStatus == text { fillStatus = nil }
        }
    }

    // MARK: Loading and observing

    func load() {
        do {
            let (jars, root, count, brine) = try store.read { db in
                let root = try store.root(db)
                return (try root.jars(db), root, try Item.fetchCount(db), try root.brine(db))
            }
            self.jars = jars
            self.itemCount = count
            self.brine = brine
            self.activeJarId = root.activeJarId ?? jars.first?.id
            loadTabs()
        } catch {
            assertionFailure("Workbench.load: \(error)")
        }
    }

    /// Today, Sealed and every open tab. `observe()` keeps these current in the app; this
    /// reads them straight after the Workbench's own writes, so they never lag a gesture.
    private func refreshSmartJars() {
        guard let smart = try? store.read({ db in
            (try store.today(db), try store.sealed(db), try Tab.fetchAll(db))
        }) else { return }
        (todayItems, sealedItems, allTabs) = smart
        forgetGlyphsOfGoneTabs()
    }

    private func loadTabs() {
        refreshSmartJars()
        guard let jarId = activeJarId, SmartJar(id: jarId) == nil else { tabs = []; activeTabId = nil; return }
        tabs = (try? store.read { db in
            try Tab.filter(Tab.Columns.jarId == jarId).order(Tab.Columns.sortOrder).fetchAll(db)
        }) ?? []
        if activeTabId == nil || !tabs.contains(where: { $0.id == activeTabId }) {
            activeTabId = tabs.first?.id
        }
    }

    func observe() async {
        let store = self.store
        let observation = ValueObservation.tracking { db -> ([Jar], Int, [Item], [Item], [Item], [Tab]) in
            let root = try store.root(db)
            return (try root.jars(db), try Item.fetchCount(db), try root.brine(db),
                    try store.today(db), try store.sealed(db), try Tab.fetchAll(db))
        }
        do {
            for try await (jars, count, brine, today, sealed, allTabs) in observation.values(in: store.dbQueue) {
                self.jars = jars
                let names = jars.map { "\($0.id)\u{1F}\($0.name)" }
                if names != jarNamesTold {
                    jarNamesTold = names
                    onJarsChanged?(jars)
                }
                self.itemCount = count
                self.brine = brine
                self.todayItems = today
                self.sealedItems = sealed
                self.allTabs = allTabs
                if activeJarId == nil || (!showingSmartJar && !jars.contains { $0.id == activeJarId }) {
                    activate(jars.first)
                }
            }
        } catch is CancellationError {
            // The window went away; nothing to keep current.
        } catch {
            assertionFailure("Workbench.observe: \(error)")
        }
    }

    /// Set by the app: called at launch and whenever a jar is added, renamed or removed, so
    /// Siri and Spotlight know the names in "Open <jar> in NetRelish".
    var onJarsChanged: (([Jar]) -> Void)?
    @ObservationIgnored private var jarNamesTold: [String]?

    /// The sweep: every few seconds, sink what is past its shelf life; every second, tick the clock.
    func runSweep() async {
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            now = Date()
            ticks += 1
            if ticks % 5 == 0 { sweep() }
        }
    }

    // MARK: Jars

    func activate(_ jar: Jar?) {
        guard let jar else { return }
        activate(jarId: jar.id)
    }

    func activate(index: Int) {
        guard jars.indices.contains(index) else { return }
        activate(jarId: jars[index].id)
    }

    func activateBrine() { activate(.brine) }
    func activate(_ smart: SmartJar) { activate(jarId: smart.id) }

    private func activate(jarId: String) {
        savedCopy = nil                   // picking a jar always leaves a saved copy
        comparison = nil
        reader = nil
        guard jarId != activeJarId else { return }
        touchActiveTab()
        activeJarId = jarId
        activeTabId = nil
        loadTabs()
        if SmartJar(id: jarId) == nil {
            try? store.write { db in
                var root = try store.root(db)
                root.activeJarId = jarId
                try root.update(db)
            }
        }
    }

    func newJar(name: String, tint: String?, shelfLifeDays: Double?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var jar = Jar(glyph: "nr-jar", isPinned: false, name: trimmed, shelfLifeDays: shelfLifeDays,
                      sortOrder: Double(jars.count), tint: tint,
                      defaultRecipeId: PantryStore.sealAndSummarizeRecipeId)   // every jar runs it on Seal
        do {
            try store.write { db in try jar.insert(db) }
            load()
            activate(jar)
        } catch {
            assertionFailure("Workbench.newJar: \(error)")
        }
    }

    func updateJar(_ jar: Jar, name: String, tint: String?, shelfLifeDays: Double?) {
        var jar = jar
        jar.name = name.trimmingCharacters(in: .whitespaces)
        jar.tint = tint
        jar.shelfLifeDays = shelfLifeDays
        do {
            try store.write { db in try jar.update(db) }
            load()
        } catch {
            assertionFailure("Workbench.updateJar: \(error)")
        }
    }

    // MARK: Tabs

    /// A new, active tab. With `jarId`, in that jar or nowhere: a jar that isn't on the Shelf
    /// gets no tab. `openedBy` is the tab whose page opened this one as a new window.
    @discardableResult
    func newTab(url: String? = nil, interactionState: Data? = nil, in jarId: String? = nil,
                openedBy openerId: String? = nil) -> Tab? {
        savedCopy = nil
        comparison = nil
        reader = nil
        let target = jarId ?? (showingSmartJar ? jars.first?.id : activeJarId)
        guard let target, jars.contains(where: { $0.id == target }) else { return nil }
        if activeJarId != target { activate(jarId: target) }
        // After the last tab, wherever that is: closing or moving a tab leaves gaps in the order.
        var tab = Tab(interactionState: interactionState, isPinned: false,
                      sortOrder: (tabs.map(\.sortOrder).max() ?? -1) + 1,
                      title: nil, touchedAt: Date(), url: url, jarId: target)
        do {
            try store.write { db in try tab.insert(db) }
            loadTabs()
            activeTabId = tab.id
            if let openerId { openerOf[tab.id] = openerId }
            return tab
        } catch {
            assertionFailure("Workbench.newTab: \(error)")
            return nil
        }
    }

    func activateTab(_ tab: Tab) {
        savedCopy = nil
        comparison = nil
        reader = nil
        guard tab.id != activeTabId else { return }
        touchActiveTab()
        activeTabId = tab.id
        touchActiveTab()
    }

    /// Which tab opened which, for tabs a page opened as new windows. Closing one goes back
    /// to its opener, the way closing a popup does in any browser.
    private var openerOf: [String: String] = [:]

    func closeTab(_ tab: Tab) {
        do {
            try store.write { db in _ = try tab.delete(db) }
            onTabsGone?([tab.id])
            if reader?.tabId == tab.id { reader = nil }
            let wasActive = tab.id == activeTabId
            let opener = openerOf.removeValue(forKey: tab.id)
            loadTabs()
            if wasActive { activeTabId = opener.flatMap { id in tabs.first { $0.id == id }?.id } ?? tabs.first?.id }
        } catch {
            assertionFailure("Workbench.closeTab: \(error)")
        }
    }

    /// ⌘W. With a saved copy showing, closes the copy, not the tab hidden behind it.
    func closeActiveTab() {
        guard !zestInFront else { return }
        if comparison != nil { comparison = nil; return }
        if savedCopy != nil { savedCopy = nil; return }
        if let benchTab { closeTab(benchTab) }
    }

    /// Closes a tab by id, in any jar, for a page that closed its own window. A pinned tab
    /// stays: only the user closes those.
    func closeTab(id: String) {
        let tab = tabs.first { $0.id == id } ?? (try? store.read { db in try Tab.fetchOne(db, key: id) })
        if let tab, !tab.isPinned { closeTab(tab) }
    }

    func togglePin(_ tab: Tab) {
        var tab = tab
        tab.isPinned.toggle()
        tab.touchedAt = Date()
        try? store.write { db in try tab.update(db) }
        loadTabs()
    }

    func togglePinActiveTab() { if let tab = pageInFront { togglePin(tab) } }

    // MARK: Rearranging (right-click and drag)

    /// Re-reads the Shelf's order after a write here, without changing which jar is showing.
    private func reloadJars() {
        if let fresh = try? store.read({ db in try store.root(db).jars(db) }) { jars = fresh }
    }

    /// Moves a jar to `index` on the Shelf. A jar only ever moves along the Shelf.
    func moveJar(_ jarId: String, to index: Int) {
        var ids = jars.map(\.id)
        guard let from = ids.firstIndex(of: jarId) else { return }
        let to = min(max(index, 0), ids.count - 1)
        guard to != from else { return }
        ids.remove(at: from)
        ids.insert(jarId, at: to)
        let order = ids
        do {
            try store.write { db in
                for (position, id) in order.enumerated() {
                    guard var jar = try Jar.fetchOne(db, key: id) else { continue }
                    jar.sortOrder = Double(position)
                    try jar.update(db)
                }
            }
            reloadJars()
        } catch {
            assertionFailure("Workbench.moveJar: \(error)")
        }
    }

    /// Move Up and Move Down in a jar's menu: one place along the Shelf.
    func moveJar(_ jar: Jar, by offset: Int) {
        guard let from = jars.firstIndex(where: { $0.id == jar.id }) else { return }
        moveJar(jar.id, to: from + offset)
    }

    /// Recolors a jar from its menu. The tint is the jar's own data (ADR 0005).
    func setTint(_ tint: String, of jar: Jar) {
        guard var fresh = jars.first(where: { $0.id == jar.id }), fresh.tint != tint else { return }
        fresh.tint = tint
        do {
            try store.write { db in try fresh.update(db) }
            reloadJars()
        } catch {
            assertionFailure("Workbench.setTint: \(error)")
        }
    }

    /// Drops a tab where another tab of the active jar is: it takes that place in the strip.
    func moveTab(_ tabId: String, onto targetId: String) {
        var ids = tabs.map(\.id)
        guard tabId != targetId, let from = ids.firstIndex(of: tabId), let to = ids.firstIndex(of: targetId) else { return }
        ids.remove(at: from)
        ids.insert(tabId, at: to)
        let order = ids
        do {
            try store.write { db in
                for (position, id) in order.enumerated() {
                    guard var tab = try Tab.fetchOne(db, key: id) else { continue }
                    tab.sortOrder = Double(position)
                    try tab.update(db)
                }
            }
            loadTabs()
        } catch {
            assertionFailure("Workbench.moveTab: \(error)")
        }
    }

    /// Moves a tab into another jar, at the end of its strip. Every jar keeps its own cookies
    /// and sign-ins (non-negotiable 6), so the page can't come along as it is: the tab keeps
    /// its address, lets go of its web view, and loads again in the new jar.
    func moveTab(_ tab: Tab, toJar jarId: String) {
        guard tab.jarId != jarId, jars.contains(where: { $0.id == jarId }),
              var moved = try? store.read({ db in try Tab.fetchOne(db, key: tab.id) }) else { return }
        moved.jarId = jarId
        moved.interactionState = nil      // history and form state belong to the jar it left
        moved.touchedAt = Date()          // its shelf life starts over in the new jar
        do {
            try store.write { db in
                let last = try Tab.filter(Tab.Columns.jarId == jarId).fetchAll(db).map(\.sortOrder).max()
                moved.sortOrder = (last ?? -1) + 1
                try moved.update(db)
            }
            onTabsGone?([moved.id])       // the web view on the old jar's store
            if reader?.tabId == moved.id { reader = nil }
            openerOf[moved.id] = nil
            loadTabs()                    // it has left this strip; the next tab comes forward
        } catch {
            assertionFailure("Workbench.moveTab(toJar:): \(error)")
        }
    }

    /// Closes every unpinned tab in the active jar except this one.
    /// One write and one reload, however many tabs go.
    func closeOtherTabs(_ keep: Tab) {
        let closing = tabs.filter { $0.id != keep.id && !$0.isPinned }
        guard !closing.isEmpty else { return }
        let ids = closing.map(\.id)
        do {
            try store.write { db in
                for tab in closing { _ = try tab.delete(db) }
            }
            onTabsGone?(ids)
            if let reading = reader?.tabId, ids.contains(reading) { reader = nil }
            for id in ids { openerOf[id] = nil }
            loadTabs()
            if tabs.contains(where: { $0.id == keep.id }) { activateTab(keep) }
        } catch {
            assertionFailure("Workbench.closeOtherTabs: \(error)")
        }
    }

    /// Something dragged was let go over a jar on the Shelf: a tab moves into that jar, a
    /// Brine row is restored into it. False if it wasn't one of ours.
    @discardableResult
    func drop(_ payloads: [String], onJar jar: Jar) -> Bool {
        var landed = false
        for payload in payloads.compactMap(DragPayload.init) {
            switch payload {
            case .tab(let id):
                guard let tab = allTabs.first(where: { $0.id == id }), tab.jarId != jar.id else { continue }
                moveTab(tab, toJar: jar.id)
                landed = true
            case .brine(let id):
                guard let item = brine.first(where: { $0.id == id }) else { continue }
                restore(item, into: jar.id)
                landed = true
            }
        }
        return landed
    }

    /// A dragged tab was let go over another tab in the strip.
    @discardableResult
    func drop(_ payloads: [String], onTab target: Tab) -> Bool {
        for case .tab(let id) in payloads.compactMap(DragPayload.init) where id != target.id {
            guard tabs.contains(where: { $0.id == id }) else { continue }
            moveTab(id, onto: target.id)
            return true
        }
        return false
    }

    // MARK: Tab icons

    func glyph(of tab: Tab) -> String? { tabGlyphs[tab.id] }

    /// Gives a tab an icon (an SF Symbol name), or takes it back with nil.
    func setGlyph(_ symbol: String?, for tab: Tab) {
        guard tabGlyphs[tab.id] != symbol else { return }
        tabGlyphs[tab.id] = symbol
        defaults.set(tabGlyphs, forKey: Self.tabGlyphsKey)
    }

    /// A closed, sealed or sunk tab's icon has nothing left to sit on.
    private func forgetGlyphsOfGoneTabs() {
        guard !tabGlyphs.isEmpty else { return }
        let open = Set(allTabs.map(\.id))
        let kept = tabGlyphs.filter { open.contains($0.key) }
        guard kept.count != tabGlyphs.count else { return }
        tabGlyphs = kept
        defaults.set(kept, forKey: Self.tabGlyphsKey)
    }

    /// Puts a tab's address on the clipboard.
    func copyLink(of tab: Tab) {
        guard let url = tab.url, !url.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    /// Navigation happened in a tab: remember where it is and that it was just used.
    ///
    /// `fromJar` is the jar of the web view reporting. Every window keeps its own web views,
    /// so a page can still be open on the store of a jar its tab has left; what that page
    /// does must never be written onto the tab (non-negotiable 6).
    func tabDidNavigate(_ tabId: String, fromJar jarId: String? = nil, url: URL?, title: String) {
        if let jarId, let known = allTabs.first(where: { $0.id == tabId }), known.jarId != jarId { return }
        // A new page in the tab leaves Reader view; a late title for the same page doesn't.
        if let reader, reader.tabId == tabId, reader.url != url?.absoluteString { self.reader = nil }
        guard var tab = tabs.first(where: { $0.id == tabId }) else { return }
        tab.url = url?.absoluteString
        tab.title = title
        tab.touchedAt = Date()
        try? store.write { db in try tab.update(db) }
        loadTabs()
    }

    private func touchActiveTab() {
        guard var tab = activeTab else { return }
        tab.touchedAt = Date()
        if let provider = interactionStateProvider { tab.interactionState = provider(tab) }
        try? store.write { db in try tab.update(db) }
    }

    // MARK: Sinking and Brine

    /// Sinks every tab in every jar that is past its shelf life. The active tab counts as
    /// touched right now, so it never sinks out from under the user.
    func sweep() {
        touchActiveTab()
        let now = Date()
        var sunk: [String] = []
        do {
            let allTabs = try store.read { db in try Tab.fetchAll(db) }
            for var tab in allTabs where tab.id != activeTabId {
                guard let jar = jars.first(where: { $0.id == tab.jarId }), ShelfLife.shouldSink(tab, in: jar, now: now) else { continue }
                if let provider = interactionStateProvider { tab.interactionState = provider(tab) ?? tab.interactionState }
                _ = try store.write { db in try tab.sink(db) }
                sunk.append(tab.id)
            }
        } catch {
            assertionFailure("Workbench.sweep: \(error)")
        }
        if !sunk.isEmpty { onTabsGone?(sunk) }
        loadTabs()
    }

    // MARK: Seal (⌘S)

    /// Set by the Bench: freezes the tab's page and pulls its text out. Stubbed in tests.
    var sealProvider: ((Tab) async throws -> (Data, Extraction.Result))?
    /// Set by the Bench: whether a tab's page is loaded in a live web view right now.
    var livePageAvailable: ((Tab) -> Bool)?
    /// Increments to run the drip. The Bench watches it; nothing else does.
    private(set) var sealTrigger = 0
    /// The jar the drip is falling into, so its badge can tick over.
    private(set) var sealingJarId: String?

    /// Seal: stamp `sealedAt`, freeze the `.webarchive`, close the tab, fire `onSeal`, and run
    /// the jar's default Recipe (non-negotiable 3). The drip starts first and the disk work
    /// happens behind it, so the gesture feels instant however heavy the page is.
    @discardableResult
    func sealActiveTab(into chosenJarId: String? = nil) async -> Bool {
        guard let tab = pageInFront, let jarId = chosenJarId ?? tab.jarId, let provider = sealProvider else {
            report("Nothing to seal — open a page first")
            return false
        }
        sealingJarId = jarId
        sealTrigger += 1

        do {
            let (archive, extracted) = try await provider(tab)
            // A Shortcut stopped while the page froze keeps nothing: no item, no Recipe.
            try Task.checkCancellation()
            try store.write { db in
                _ = try store.sealPage(
                    db, url: tab.url,
                    title: extracted.title.isEmpty ? (tab.title ?? tab.url ?? "Untitled") : extracted.title,
                    body: extracted.body, excerpt: extracted.excerpt,
                    archive: archive, jarId: jarId, source: .browse)
            }
            closeIfStillOn(tab)
            report("Sealed into \(jars.first { $0.id == jarId }?.name ?? "the jar")")
            summarizeWaiting()
            stampWaiting()
            return true
        } catch is CancellationError {
            return false
        } catch {
            log.error("seal: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t seal this page")
            return false
        }
    }

    // MARK: Seal from Shortcuts

    /// What an off-screen load hands Seal: the frozen page, its text, and where it ended up.
    struct OffscreenPage: Sendable {
        var archive: Data
        var extracted: Extraction.Result
        var url: String
        var title: String?
    }

    /// Loads a page off screen in a jar's profile (non-negotiable 6) and freezes it. The real
    /// loader by default; tests stub it, as they stub `sealProvider`.
    var offscreenLoader: @MainActor (URL, String) async throws -> OffscreenPage = { url, jarId in
        try await Workbench.loadOffscreen(url, jarId: jarId)
    }

    static func loadOffscreen(_ url: URL, jarId: String) async throws -> OffscreenPage {
        let page = HeadlessPage(jarId: jarId)
        try await page.load(url)
        let extracted = try await Extraction.run(in: page.webView)   // while the page is live
        let archive = try await page.webView.dataForWebArchive()
        return OffscreenPage(archive: archive, extracted: extracted,
                             url: page.webView.url?.absoluteString ?? url.absoluteString,
                             title: page.webView.title)
    }

    /// Shortcuts' Seal with a link: a full Seal of a page that isn't open, the same as ⌘S
    /// would make of it. Into `jarId`, or the jar the page was last kept in, else the active
    /// jar, else the first on the Shelf. The page loads in that jar's profile, unless
    /// `profileJarId` names another (a tab's own jar, whose sign-ins the page was open with).
    @discardableResult
    func sealPage(at url: URL, into jarId: String?, profileJarId: String? = nil,
                  source: CaptureSource = .shortcut) async throws -> Item {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ShortcutError.notAWebPage
        }
        let target: Jar = try store.read { db in
            if let jarId {
                guard let jar = try Jar.fetchOne(db, key: jarId) else { throw ShortcutError.jarGone }
                return jar
            }
            guard let jar = try store.jarForSealing(db, url: url.absoluteString) else { throw ShortcutError.noJar }
            return jar
        }
        let page: OffscreenPage
        do {
            page = try await offscreenLoader(url, profileJarId ?? target.id)
        } catch let failure as HeadlessPage.Failure {
            log.error("offscreen seal: the page didn't load (\(failure.description, privacy: .private))")
            throw ShortcutError.pageDidNotLoad(failure.description)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Freezing or reading the page went wrong, not loading it. The details are for
            // the log; the person gets a plain sentence.
            log.error("offscreen seal: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            throw ShortcutError.couldNotSeal
        }
        // A Shortcut cancelled while the page loaded keeps nothing: no item, no Recipe.
        try Task.checkCancellation()
        let title = page.extracted.title.isEmpty
            ? (page.title?.isEmpty == false ? page.title! : page.url)
            : page.extracted.title
        let item = try store.write { db in
            try store.sealPage(db, url: page.url, title: title, body: page.extracted.body,
                               excerpt: page.extracted.excerpt, archive: page.archive,
                               jarId: target.id, source: source)
        }
        refreshSmartJars()
        report("Sealed into \(target.name)")
        summarizeWaiting()
        stampWaiting()
        return item
    }

    /// Shortcuts' Seal with no link: the page in front, as ⌘S seals it, into `jarId` if the
    /// Shortcut names one, else the tab's own jar. If the page isn't loaded in a live web view
    /// (no window, or a tab not shown yet), it's loaded off screen instead. Either way the tab
    /// closes, the way ⌘S closes it. Returns the sealed page's title.
    func sealFrontPage(into jarId: String? = nil) async throws -> String {
        guard let tab = pageInFront, let link = tab.url, let url = URL(string: link) else {
            throw ShortcutError.nothingOpen
        }
        if let jarId, !jars.contains(where: { $0.id == jarId }) { throw ShortcutError.jarGone }
        let title = tab.title?.isEmpty == false ? tab.title! : link
        if sealProvider != nil, livePageAvailable?(tab) == true {
            guard await sealActiveTab(into: jarId) else {
                try Task.checkCancellation()
                throw ShortcutError.couldNotSeal
            }
            return title
        }
        // Loaded in the tab's own jar, so the page is the one its sign-ins show, as ⌘S would
        // freeze it (non-negotiable 6), then kept in the jar named.
        let item = try await sealPage(at: url, into: jarId ?? tab.jarId, profileJarId: tab.jarId)
        closeIfStillOn(tab)
        return item.title
    }

    /// Closes a tab after Seal, unless it went to another page while Seal worked: then only
    /// the page it was on is sealed, and the page it's on now stays open.
    private func closeIfStillOn(_ tab: Tab) {
        let now = tabs.first { $0.id == tab.id } ?? (try? store.read { db in try Tab.fetchOne(db, key: tab.id) })
        // Same page, same jar. A tab that navigated on, or was moved to another jar while the
        // page was being frozen, is no longer the tab that was sealed, and stays open.
        guard let now, now.url == tab.url, now.jarId == tab.jarId else { return }
        closeTab(now)
    }

    /// Shortcuts' "Open a Jar": shows the jar on the Bench. False if it no longer exists.
    @discardableResult
    func show(jarId: String) -> Bool {
        guard jars.contains(where: { $0.id == jarId }) else { return false }
        activate(jarId: jarId)
        return true
    }

    // MARK: Reseal & diff (Pro)

    /// Two seals of the same page, side by side on the Bench. `diff` is nil while it's worked out.
    struct Comparison: Equatable {
        let older: Item
        let newer: Item
        var diff: PageDiff?
        /// Neither seal kept any article text, so there is nothing to compare.
        var hasText: Bool { !(older.body ?? "").isEmpty || !(newer.body ?? "").isEmpty }
    }

    /// The comparison the Bench is showing, over everything else.
    private(set) var comparison: Comparison?
    /// The page being sealed again, by URL, while its fresh copy loads.
    private(set) var resealingURL: String?

    /// Every seal of a page, newest first.
    func seals(of item: Item) -> [Item] {
        guard let url = item.url else { return [] }
        return (try? store.read { db in try store.seals(db, url: url) }) ?? []
    }

    /// Seals the page again, in its own jar's profile, and compares the new seal with the latest
    /// one before it. The earlier seal is never touched (non-negotiable 3).
    func resealAndCompare(_ item: Item) async {
        pro.settle()   // a year that ran out since launch locks here, without a call
        guard pro.isUnlocked else { showingPro = true; return }
        guard let link = item.url, let url = URL(string: link) else {
            report("This page has no link to seal again")
            return
        }
        guard resealingURL == nil else { return }
        resealingURL = link
        defer { resealingURL = nil }
        let before = seals(of: item).first ?? item
        do {
            let fresh = try await sealPage(at: url, into: item.jarId ?? before.jarId, source: .browse)
            await compare(before, fresh)
        } catch is CancellationError {
            return
        } catch {
            log.error("reseal: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t seal this page again")
        }
    }

    /// Compares a seal with the one before it.
    func compareWithPrevious(_ item: Item) async {
        guard let older = try? store.read({ db in try store.previousSeal(db, before: item) }) else {
            report("This page has only been sealed once")
            return
        }
        await compare(older, item)
    }

    /// Shows two seals side by side. The difference is worked out off the main thread, so a
    /// long page never stalls the window.
    func compare(_ older: Item, _ newer: Item) async {
        pro.settle()   // a year that ran out since launch locks here, without a call
        guard pro.isUnlocked else { showingPro = true; return }
        // A saved copy open underneath stays open: Done goes back to it.
        comparison = Comparison(older: older, newer: newer, diff: nil)
        let (a, b) = (older.body ?? "", newer.body ?? "")
        let diff = await Task.detached(priority: .userInitiated) { PageDiff(old: a, new: b) }.value
        guard comparison?.older.id == older.id, comparison?.newer.id == newer.id else { return }
        comparison?.diff = diff
    }

    /// Back to whatever the Bench showed before.
    func closeComparison() { comparison = nil }

    // MARK: The Panel (⌘⌥I)

    /// The right column (manifest §8, ADR 0010 row 9: "Panel", never "Inspector"). Shown
    /// unless you hide it; the choice is remembered.
    var showPanel: Bool = UserDefaults.standard.object(forKey: "panel.visible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPanel, forKey: "panel.visible") }
    }

    /// What the Panel describes: whatever the Bench is showing.
    enum PanelSubject: Equatable {
        case savedCopy(Item)
        case tab(Tab)
        case jar(Jar)
        case smartJar(SmartJar)
        case nothing
    }

    var panelSubject: PanelSubject {
        if let comparison { return .savedCopy(comparison.newer) }
        if let savedCopy { return .savedCopy(savedCopy) }
        if let smart = activeSmartJar { return .smartJar(smart) }
        if let tab = benchTab { return .tab(tab) }
        if let jar = activeJar { return .jar(jar) }
        return .nothing
    }

    /// Bumped whenever a label changes, so the Panel reads them again.
    private(set) var labelRevision = 0

    /// The Pantry's item for a page, if it was captured or sealed.
    func pantryItem(for url: String?) -> Item? {
        guard let url, !url.isEmpty else { return nil }
        return try? store.read { db in try store.item(db, url: url) }
    }

    func labels(of item: Item) -> [Label] {
        (try? store.read { db in try item.labels(db) })?.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } ?? []
    }

    func addLabel(_ name: String, to item: Item) {
        do {
            try store.write { db in _ = try store.addLabel(db, named: name, to: item) }
            labelRevision += 1
        } catch {
            log.error("label: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t add that label")
        }
    }

    func removeLabel(_ label: Label, from item: Item) {
        do {
            try store.write { db in try store.removeLabel(db, label, from: item) }
            labelRevision += 1
        } catch {
            log.error("label: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t remove that label")
        }
    }

    /// A jar's name for display, or Brine for an item with no jar.
    func jarName(for id: String?) -> String {
        id.flatMap { id in jars.first { $0.id == id }?.name } ?? "Brine"
    }

    // MARK: Reader view (⌘⇧R)

    /// The article Reader view is showing, and the tab and page it came from.
    struct ReaderState: Equatable {
        let tabId: String
        let url: String?
        let article: Extraction.Article
    }

    private(set) var reader: ReaderState?
    /// Set by the Bench: pulls the article out of the tab's live page. Stubbed in tests.
    var readerProvider: ((Tab) async throws -> Extraction.Article?)?

    /// Reader view is showing for the tab on the Bench.
    var isReading: Bool { reader != nil && reader?.tabId == benchTab?.id }

    /// ⌘⇧R. Shows the page's article alone in clean type, or goes back to the page. Pages
    /// with no article (a home page, a search) say so and stay as they are.
    func toggleReader() async {
        guard !zestInFront else { return }
        if isReading { reader = nil; return }
        guard let tab = pageInFront, let provider = readerProvider else {
            report("Nothing to read — open a page first")
            return
        }
        do {
            guard let article = try await provider(tab) else {
                report("This page has no article to read")
                return
            }
            // You moved on while it was reading, or the tab moved to another jar: the article
            // was read with the old jar's sign-ins and must not show over the new jar's page.
            guard benchTab?.id == tab.id, benchTab?.jarId == tab.jarId else { return }
            // The page the article came from, which can be ahead of the tab's saved URL while
            // a heavy page is still loading.
            reader = ReaderState(tabId: tab.id, url: article.url ?? tab.url, article: article)
        } catch {
            log.error("reader: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Reader view couldn’t read this page")
        }
    }

    /// Back to the live page.
    func closeReader() { reader = nil }

    // MARK: The palette (⌘K)

    /// ⌘K. The palette is a sheet over the Bench; nothing else changes while it's open.
    var showPalette = false

    /// ⌘D. Puts the active tab's page in Brine as an Item. It does NOT seal — no webarchive,
    /// no `sealedAt` — that's P2. The generated `capture` titles the item with its URL, so the
    /// tab's real title is written over it here.
    func captureActivePage() {
        guard let tab = pageInFront, let url = tab.url, !url.isEmpty else {
            report("Nothing to capture — open a page first")
            return
        }
        do {
            try store.write { db in
                var item = try store.root(db).capture(db, url: url)
                if let title = tab.title, !title.isEmpty, title != url {
                    item.title = title
                    item.updatedAt = Date()
                    try item.update(db)
                }
            }
            refreshSmartJars()
            report("Captured into Brine")   // the ValueObservation refreshes Brine on its own
        } catch {
            log.error("capture: \(errorKind(error), privacy: .public) \(String(describing: error), privacy: .private)")
            report("Couldn’t capture this page")
        }
    }

    /// Full-text search over the Pantry. Failures return nothing rather than throwing into a view.
    func searchPantry(_ query: String) -> [Item] {
        (try? store.read { db in try store.search(db, query) }) ?? []
    }

    /// The sealed item whose saved copy is showing, or nil. The Bench presents it, over the
    /// active tab, which stays open behind it.
    var savedCopy: Item?

    /// Opens a Pantry item. A sealed one opens its saved copy, the page as it was when sealed.
    /// Anything else opens its tab if one is already open, else a new tab in its jar.
    func open(_ item: Item) {
        if item.state == .sealed, item.snapshotPath != nil {
            comparison = nil
            savedCopy = item
            return
        }
        // Already open in some jar: go to that tab rather than open a second one.
        if let url = item.url, let existing = allTabs.first(where: { $0.url == url }),
           let jarId = existing.jarId, jars.contains(where: { $0.id == jarId }) {
            activate(jarId: jarId)
            if let tab = tabs.first(where: { $0.id == existing.id }) { activateTab(tab) }
            return
        }
        // Its own jar, or the jar it sank from (the jar on its chip, with that jar's sign-ins,
        // as Restore does). An item with neither opens where ⌘T would.
        let home = (item.jarId ?? item.sunkOriginJarId).flatMap { id in jars.first { $0.id == id }?.id }
        newTab(url: item.url, interactionState: item.sunkInteractionState, in: home)
    }

    /// The live page behind a saved copy, in a new tab in the item's jar, or in the jar
    /// you're in if that one is gone.
    func openLivePage(_ item: Item) {
        savedCopy = nil
        guard let url = item.url else { return }
        newTab(url: url, in: item.jarId.flatMap { id in jars.first { $0.id == id }?.id })
    }

    /// A link clicked inside a saved copy: the live page, in a new tab in the copy's jar.
    func openLink(_ url: URL, from item: Item) {
        savedCopy = nil
        newTab(url: url.absoluteString, in: item.jarId.flatMap { id in jars.first { $0.id == id }?.id })
    }

    /// The archive bytes for a sealed item, or nil if the file is gone.
    func snapshotData(for item: Item) -> Data? {
        guard let path = item.snapshotPath else { return nil }
        return try? store.snapshots.read(path)
    }

    /// Opens a tab from Sinking soon: its jar, then the tab, touched so its shelf life starts
    /// over. Only the touch is written, so the tab keeps the scroll and history it had.
    func open(_ tab: Tab) {
        guard let jarId = tab.jarId, jars.contains(where: { $0.id == jarId }) else { return }
        activate(jarId: jarId)
        guard var fresh = tabs.first(where: { $0.id == tab.id }) else { return }
        activeTabId = fresh.id
        fresh.touchedAt = Date()
        try? store.write { db in try fresh.update(db) }
        loadTabs()
    }

    /// Reopens a Brine item as a tab, with its scroll and history, in the jar it sank from
    /// (or the first jar). The item stays in Brine: closing is free, so is restoring.
    ///
    /// With `jarId`, in that jar instead (dragged there, or picked from the row's menu). Its
    /// scroll and history come along only into the jar it sank from: they were made with that
    /// jar's sign-ins, and those never cross jars (non-negotiable 6).
    func restore(_ item: Item, into jarId: String? = nil) {
        let origin = item.sunkOriginJarId.flatMap { id in jars.first { $0.id == id }?.id }
        let target = jarId.flatMap { id in jars.first { $0.id == id }?.id } ?? origin ?? jars.first?.id
        let state = (jarId == nil || target == origin) ? item.sunkInteractionState : nil
        newTab(url: item.url, interactionState: state, in: target)
    }
}
