// Workbench.swift — the app's live state: the jars on the Shelf, the active jar, its tabs,
// the active tab, Brine, and the sweep that sinks idle tabs. Observed by everything.

import Foundation
import GRDB
import Observation
import OSLog
import Pantry

private let log = Logger(subsystem: "com.shepdesign.netrelish", category: "workbench")

/// SwiftUI has its own `Tab`; in this app the word means the Pantry's.
typealias Tab = Pantry.Tab

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
    var benchTab: Tab? { savedCopy == nil && !showingSmartJar ? activeTab : nil }

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

    init(store: PantryStore = .shared, vault: VaultStore = .live, inbox: ShareInbox? = nil) {
        self.store = store
        self.vault = vault
        self.inbox = inbox
        load()
    }

    // MARK: The Share extension

    /// Takes in whatever was shared from another app's Share menu since the last look, into
    /// Brine. Runs at launch, when the app comes forward, and with every sweep, so a page
    /// shared from Safari is in Brine within seconds even while NetRelish is behind it.
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
            log.error("share: \(String(describing: error), privacy: .public)")
            report("Couldn’t take in a shared page. It will be tried again.")
        }
    }

    // MARK: Fill from Me

    /// Bench → Fill from Me (⌘⇧F). The jar's own card wins over Me. Never runs on its own,
    /// and never into a page Reader view is covering: you'd be filling fields you can't see.
    func fillFromMe() {
        if isReading { report("Go back to the page to fill a form"); return }
        guard let tab = benchTab, let filler = formFiller else { return }
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
                log.error("fill: \(String(describing: error), privacy: .public)")
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
                self.itemCount = count
                self.brine = brine
                self.todayItems = today
                self.sealedItems = sealed
                self.allTabs = allTabs
                if activeJarId == nil || (!showingSmartJar && !jars.contains { $0.id == activeJarId }) {
                    activate(jars.first)
                }
            }
        } catch {
            assertionFailure("Workbench.observe: \(error)")
        }
    }

    /// The sweep: every few seconds, sink what is past its shelf life and take in shared pages;
    /// every second, tick the clock.
    func runSweep() async {
        receiveShared()
        var ticks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            now = Date()
            ticks += 1
            if ticks % 5 == 0 {
                sweep()
                receiveShared()
            }
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
                      sortOrder: Double(jars.count), tint: tint)
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
        reader = nil
        let target = jarId ?? (showingSmartJar ? jars.first?.id : activeJarId)
        guard let target, jars.contains(where: { $0.id == target }) else { return nil }
        if activeJarId != target { activate(jarId: target) }
        var tab = Tab(interactionState: interactionState, isPinned: false, sortOrder: Double(tabs.count),
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

    func togglePinActiveTab() { if let benchTab { togglePin(benchTab) } }

    /// Navigation happened in a tab: remember where it is and that it was just used.
    func tabDidNavigate(_ tabId: String, url: URL?, title: String) {
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
    /// Increments to run the drip. The Bench watches it; nothing else does.
    private(set) var sealTrigger = 0
    /// The jar the drip is falling into, so its badge can tick over.
    private(set) var sealingJarId: String?

    /// Seal: stamp `sealedAt`, freeze the `.webarchive`, close the tab, fire `onSeal`, and run
    /// the jar's default Recipe (non-negotiable 3). The drip starts first and the disk work
    /// happens behind it, so the gesture feels instant however heavy the page is.
    func sealActiveTab() async {
        guard let tab = benchTab, let jarId = tab.jarId, let provider = sealProvider else {
            report("Nothing to seal — open a page first")
            return
        }
        sealingJarId = jarId
        sealTrigger += 1

        do {
            let (archive, extracted) = try await provider(tab)
            let now = Date()
            try store.write { db in
                var item = Item(
                    body: extracted.body.isEmpty ? nil : extracted.body,
                    createdAt: now,
                    domain: tab.url.flatMap { URL(string: $0)?.host },
                    excerpt: extracted.excerpt.isEmpty ? nil : extracted.excerpt,
                    kind: .page,
                    source: .browse,
                    state: .brined,
                    title: extracted.title.isEmpty ? (tab.title ?? tab.url ?? "Untitled") : extracted.title,
                    updatedAt: now,
                    url: tab.url,
                    jarId: jarId
                )
                try item.insert(db)
                // The id names the file, so the archive is written after the insert.
                item.snapshotPath = try store.snapshots.write(archive, for: item.id)
                try item.update(db)
                _ = try store.root(db).seal(db, item: item)

                // The jar's default Recipe, if it has one. P3 gives it an editor.
                if let jar = try Jar.fetchOne(db, key: jarId), let recipeId = jar.defaultRecipeId,
                   let recipe = try Recipe.fetchOne(db, key: recipeId),
                   let sealed = try Item.fetchOne(db, key: item.id) {
                    _ = try store.root(db).runRecipe(db, recipe: recipe, items: [sealed])
                }
            }
            closeTab(tab)
            report("Sealed into \(jars.first { $0.id == jarId }?.name ?? "the jar")")
        } catch {
            log.error("seal: \(String(describing: error), privacy: .public)")
            report("Couldn’t seal this page")
        }
    }

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
            log.error("label: \(String(describing: error), privacy: .public)")
            report("Couldn’t add that label")
        }
    }

    func removeLabel(_ label: Label, from item: Item) {
        do {
            try store.write { db in try store.removeLabel(db, label, from: item) }
            labelRevision += 1
        } catch {
            log.error("label: \(String(describing: error), privacy: .public)")
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
        if isReading { reader = nil; return }
        guard let tab = benchTab, let provider = readerProvider else {
            report("Nothing to read — open a page first")
            return
        }
        do {
            guard let article = try await provider(tab) else {
                report("This page has no article to read")
                return
            }
            guard benchTab?.id == tab.id else { return }    // you moved on while it was reading
            // The page the article came from, which can be ahead of the tab's saved URL while
            // a heavy page is still loading.
            reader = ReaderState(tabId: tab.id, url: article.url ?? tab.url, article: article)
        } catch {
            log.error("reader: \(String(describing: error), privacy: .public)")
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
        guard let tab = benchTab, let url = tab.url, !url.isEmpty else {
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
            log.error("capture: \(String(describing: error), privacy: .public)")
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
    func restore(_ item: Item) {
        let target = item.sunkOriginJarId.flatMap { id in jars.first { $0.id == id }?.id } ?? jars.first?.id
        newTab(url: item.url, interactionState: item.sunkInteractionState, in: target)
    }
}
