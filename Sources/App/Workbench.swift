// Workbench.swift — the app's live state: the jars on the Shelf, the active jar, its tabs,
// the active tab, Brine, and the sweep that sinks idle tabs. Observed by everything.

import Foundation
import GRDB
import Observation
import Pantry

/// SwiftUI has its own `Tab`; in this app the word means the Pantry's.
typealias Tab = Pantry.Tab

/// The Shelf's one smart jar for now. Not a row: Brine is a query (non-negotiable 2).
enum SmartJar {
    static let brineId = "smart:brine"
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
    private(set) var itemCount = 0
    /// Ticks once a second so the strip can fade tabs in their last 10%.
    private(set) var now = Date()

    /// Set by the Jars menu; the Shelf presents the sheet.
    var jarToEdit: Jar?
    func requestEditActiveJar() { jarToEdit = activeJar }

    /// Called before a tab sinks so the Bench can hand over the web view's interaction state.
    var interactionStateProvider: ((Tab) -> Data?)?

    // MARK: Vault (the Me card)

    let vault: VaultStore
    /// Set by the Bench: fills `identity` into the tab's web view, returns the count.
    var formFiller: ((Tab, Identity) async throws -> Int)?
    /// One line in the address bar for a couple of seconds after ⌘⇧F.
    private(set) var fillStatus: String?
    /// ⌘⇧F with an empty card opens onboarding instead of filling.
    var showMeOnboarding = false

    var activeJar: Jar? { jars.first { $0.id == activeJarId } }
    var showingBrine: Bool { activeJarId == SmartJar.brineId }
    var activeTab: Tab? { tabs.first { $0.id == activeTabId } }

    init(store: PantryStore = .shared, vault: VaultStore = .live) {
        self.store = store
        self.vault = vault
        load()
    }

    // MARK: Fill from Me

    /// Bench → Fill from Me (⌘⇧F). The jar's own card wins over Me. Never runs on its own.
    func fillFromMe() {
        guard let tab = activeTab, let filler = formFiller else { return }
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
                report("Couldn’t fill: \(error)")
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

    private func loadTabs() {
        guard let jarId = activeJarId, jarId != SmartJar.brineId else { tabs = []; activeTabId = nil; return }
        tabs = (try? store.read { db in
            try Tab.filter(Tab.Columns.jarId == jarId).order(Tab.Columns.sortOrder).fetchAll(db)
        }) ?? []
        if activeTabId == nil || !tabs.contains(where: { $0.id == activeTabId }) {
            activeTabId = tabs.first?.id
        }
    }

    func observe() async {
        let observation = ValueObservation.tracking { db -> ([Jar], Int, [Item]) in
            let root = try PantryStore.shared.root(db)
            return (try root.jars(db), try Item.fetchCount(db), try root.brine(db))
        }
        do {
            for try await (jars, count, brine) in observation.values(in: store.dbQueue) {
                self.jars = jars
                self.itemCount = count
                self.brine = brine
                if activeJarId == nil || (activeJarId != SmartJar.brineId && !jars.contains { $0.id == activeJarId }) {
                    activate(jars.first)
                }
            }
        } catch {
            assertionFailure("Workbench.observe: \(error)")
        }
    }

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

    func activateBrine() { activate(jarId: SmartJar.brineId) }

    private func activate(jarId: String) {
        guard jarId != activeJarId else { return }
        touchActiveTab()
        activeJarId = jarId
        activeTabId = nil
        loadTabs()
        if jarId != SmartJar.brineId {
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

    @discardableResult
    func newTab(url: String? = nil, interactionState: Data? = nil, in jarId: String? = nil) -> Tab? {
        let target = jarId ?? (showingBrine ? jars.first?.id : activeJarId)
        guard let target, target != SmartJar.brineId else { return nil }
        if activeJarId != target { activate(jarId: target) }
        var tab = Tab(interactionState: interactionState, isPinned: false, sortOrder: Double(tabs.count),
                      title: nil, touchedAt: Date(), url: url, jarId: target)
        do {
            try store.write { db in try tab.insert(db) }
            loadTabs()
            activeTabId = tab.id
            return tab
        } catch {
            assertionFailure("Workbench.newTab: \(error)")
            return nil
        }
    }

    func activateTab(_ tab: Tab) {
        guard tab.id != activeTabId else { return }
        touchActiveTab()
        activeTabId = tab.id
        touchActiveTab()
    }

    func closeTab(_ tab: Tab) {
        do {
            try store.write { db in _ = try tab.delete(db) }
            let wasActive = tab.id == activeTabId
            loadTabs()
            if wasActive { activeTabId = tabs.first?.id }
        } catch {
            assertionFailure("Workbench.closeTab: \(error)")
        }
    }

    func closeActiveTab() { if let activeTab { closeTab(activeTab) } }

    func togglePin(_ tab: Tab) {
        var tab = tab
        tab.isPinned.toggle()
        tab.touchedAt = Date()
        try? store.write { db in try tab.update(db) }
        loadTabs()
    }

    func togglePinActiveTab() { if let activeTab { togglePin(activeTab) } }

    /// Navigation happened in a tab: remember where it is and that it was just used.
    func tabDidNavigate(_ tabId: String, url: URL?, title: String) {
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
        do {
            let allTabs = try store.read { db in try Tab.fetchAll(db) }
            for var tab in allTabs where tab.id != activeTabId {
                guard let jar = jars.first(where: { $0.id == tab.jarId }), ShelfLife.shouldSink(tab, in: jar, now: now) else { continue }
                if let provider = interactionStateProvider { tab.interactionState = provider(tab) ?? tab.interactionState }
                try store.write { db in try tab.sink(db) }
            }
        } catch {
            assertionFailure("Workbench.sweep: \(error)")
        }
        loadTabs()
    }

    /// Reopens a Brine item as a tab, with its scroll and history, in the jar it sank from
    /// (or the first jar). The item stays in Brine: closing is free, so is restoring.
    func restore(_ item: Item) {
        let target = item.sunkOriginJarId.flatMap { id in jars.first { $0.id == id }?.id } ?? jars.first?.id
        newTab(url: item.url, interactionState: item.sunkInteractionState, in: target)
    }
}
