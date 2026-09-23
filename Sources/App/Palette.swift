// Palette.swift — the rows ⌘K shows and where they come from. Commands and jars are matched
// locally (PaletteMatcher); Pantry results come from FTS5, which has been indexing since P0.
// A row is a title, an optional subtitle, an optional shortcut, and what to do.

import Pantry
import SwiftUI

struct PaletteRow: Identifiable {
    enum Kind { case command, jar, item }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String?
    var shortcut: String?
    /// The jar glyph's tint for jar rows (ADR 0005: a tint only ever paints its own jar).
    var tint: Color?
    let run: @MainActor () -> Void

    var symbol: NRSymbol? { kind == .jar ? .jar : nil }
    var systemImage: String? {
        switch kind {
        case .command: "chevron.right"
        case .jar: nil
        case .item: "doc.text"
        }
    }
}

@MainActor
enum PaletteSource {
    /// Commands and jars, filtered and ranked. Pantry results are appended separately,
    /// because they arrive from a database read.
    static func rows(for query: String, workbench: Workbench) -> [PaletteRow] {
        var scored: [(row: PaletteRow, score: Int)] = []
        for row in commands(workbench) + jars(workbench) {
            guard let score = PaletteMatcher.score(row.title, query: query) else { continue }
            scored.append((row, score))
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.row)
    }

    static func commands(_ workbench: Workbench) -> [PaletteRow] {
        var rows: [PaletteRow] = []
        if workbench.activeTab != nil {
            rows.append(PaletteRow(id: "cmd.capture", kind: .command, title: "Capture this page",
                                   subtitle: "Into Brine", shortcut: "⌘D") { workbench.captureActivePage() })
            rows.append(PaletteRow(id: "cmd.fill", kind: .command, title: "Fill this form",
                                   subtitle: "From your card", shortcut: "⌘⇧F") { workbench.fillFromMe() })
            rows.append(PaletteRow(id: "cmd.close", kind: .command, title: "Close Tab", shortcut: "⌘W") { workbench.closeActiveTab() })
            let pinned = workbench.activeTab?.isPinned == true
            rows.append(PaletteRow(id: "cmd.pin", kind: .command, title: pinned ? "Unpin Tab" : "Pin Tab",
                                   shortcut: "⌘⇧P") { workbench.togglePinActiveTab() })
        }
        if workbench.activeJar != nil {
            rows.append(PaletteRow(id: "cmd.newtab", kind: .command, title: "New Tab", shortcut: "⌘T") { _ = workbench.newTab() })
            rows.append(PaletteRow(id: "cmd.editjar", kind: .command, title: "Edit Jar", shortcut: "⌘⇧E") { workbench.requestEditActiveJar() })
        }
        return rows
    }

    static func jars(_ workbench: Workbench) -> [PaletteRow] {
        var rows = workbench.jars.map { jar in
            PaletteRow(id: "jar.\(jar.id)", kind: .jar, title: jar.name, subtitle: "Jar",
                       tint: jar.tint.flatMap(OKLCH.init)?.color) { workbench.activate(jar) }
        }
        rows.append(PaletteRow(id: "jar.brine", kind: .jar, title: "Brine", subtitle: "Everything unsorted",
                               shortcut: "⌘⇧1") { workbench.activateBrine() })
        return rows
    }

    /// Full-text hits, newest-best first. Empty query means no search at all.
    static func pantryRows(for query: String, workbench: Workbench) -> [PaletteRow] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let items = workbench.searchPantry(query)
        return items.prefix(8).map { item in
            let jarName = workbench.jars.first { $0.id == item.jarId }?.name
            return PaletteRow(id: "item.\(item.id)", kind: .item, title: item.title ?? item.url ?? "Untitled",
                              subtitle: jarName ?? "Brine") { workbench.open(item) }
        }
    }
}
