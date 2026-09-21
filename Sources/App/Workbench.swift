// Workbench.swift — the app's live state: the jars on the Shelf, which one is active,
// and the Pantry it all reads from. Observed by the Shelf, the Bench, and the window title.

import Foundation
import GRDB
import Observation
import Pantry

@MainActor
@Observable
final class Workbench {
    let store: PantryStore
    private(set) var jars: [Jar] = []
    private(set) var activeJarId: String?
    private(set) var itemCount = 0

    var activeJar: Jar? { jars.first { $0.id == activeJarId } }

    init(store: PantryStore = .shared) {
        self.store = store
        load()
    }

    /// Reads the Shelf and the active jar from the Pantry. The root row remembers
    /// which jar was active, so it survives relaunch.
    func load() {
        do {
            let (jars, root, count) = try store.read { db in
                (try store.root(db).jars(db), try store.root(db), try Item.fetchCount(db))
            }
            self.jars = jars
            self.itemCount = count
            self.activeJarId = root.activeJarId ?? jars.first?.id
        } catch {
            assertionFailure("Workbench.load: \(error)")
        }
    }

    /// Keeps `jars` and `itemCount` current as the Pantry changes (captures from Shortcuts, for one).
    func observe() async {
        let observation = ValueObservation.tracking { db -> ([Jar], Int) in
            (try Jar.order(Jar.Columns.sortOrder).fetchAll(db), try Item.fetchCount(db))
        }
        do {
            for try await (jars, count) in observation.values(in: store.dbQueue) {
                self.jars = jars
                self.itemCount = count
                if activeJarId == nil || !jars.contains(where: { $0.id == activeJarId }) {
                    activeJarId = jars.first?.id
                }
            }
        } catch {
            assertionFailure("Workbench.observe: \(error)")
        }
    }

    /// Switch the active jar. ⌘1–9 and the Shelf both land here.
    func activate(_ jar: Jar) {
        guard jar.id != activeJarId else { return }
        activeJarId = jar.id
        try? store.write { db in
            var root = try store.root(db)
            root.activeJarId = jar.id
            try root.update(db)
        }
    }

    func activate(index: Int) {
        guard jars.indices.contains(index) else { return }
        activate(jars[index])
    }

    /// A new jar at the end of the Shelf, made active.
    func newJar(name: String, tint: String?, shelfLifeDays: Double) {
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
}
