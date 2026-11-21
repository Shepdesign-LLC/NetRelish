// Palette.swift — the rows ⌘K shows and where they come from. Commands and jars are matched
// locally (PaletteMatcher), and so are the open tabs; Pantry results come from FTS5, which has
// been indexing since P0. A row is a title, an optional subtitle, an optional shortcut, and
// what to do. The palette shows them in three groups (manifest v2.1 §8): Pantry, Open tabs,
// Commands (jars count as commands: picking one goes there).

import Pantry
import SwiftUI

struct PaletteRow: Identifiable {
    enum Kind { case command, jar, item, tab }
    /// The palette's three groups, in the order it shows them.
    enum Group { case pantry, tabs, commands }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String?
    var shortcut: String?
    /// The jar glyph's tint for jar rows (ADR 0005: a tint only ever paints its own jar).
    var tint: Color?
    /// The page's address, for the letter tile of an item or an open tab.
    var url: String?
    /// The jar a row comes from (an item's, an open tab's, or the jar itself); nil for Brine.
    var jarId: String?
    /// The stored tint (css) of that jar, for its mini jar.
    var jarTint: String?
    /// A sealed item: the row's source reads "Sealed · <jar>".
    var sealed: Bool = false
    /// The icon picked for an open tab, if any (TabGlyph).
    var glyph: String?
    let run: @MainActor () -> Void

    var group: Group {
        switch kind {
        case .item: .pantry
        case .tab: .tabs
        case .command, .jar: .commands
        }
    }

    var symbol: NRSymbol? { kind == .jar ? .jar : nil }

    /// What VoiceOver says for the row: its title, then where it comes from or what it does,
    /// then its shortcut. "Pricing, sealed, Client site"; "Docs, open tab, Client site";
    /// "Seal this page, Into the jar, frozen, ⌘S".
    var spokenLabel: String {
        var parts = [title]
        switch kind {
        case .item:
            if sealed { parts.append("sealed") }
            parts.append(subtitle ?? "Brine")
        case .tab:
            parts.append("open tab")
            if let subtitle { parts.append(subtitle) }
        case .command, .jar:
            if let subtitle { parts.append(subtitle) }
            if let shortcut { parts.append(shortcut) }
        }
        return parts.joined(separator: ", ")
    }

    /// A command's SF Symbol. Seal has none here: the view draws NRSymbol.seal (#nr-seal).
    var systemImage: String? {
        switch kind {
        case .command:
            if id == "cmd.seal" { return nil }
            return Self.commandSymbols[id] ?? "chevron.right"
        case .jar, .tab:
            return nil
        case .item:
            return url == nil ? "doc.text" : nil
        }
    }

    /// Each command's SF Symbol, by row id. "cmd.seal" is left out on purpose.
    private static let commandSymbols: [String: String] = [
        "cmd.capture": "tray.and.arrow.down",
        "cmd.reader": "doc.plaintext",
        "cmd.fill": "person.text.rectangle",
        "cmd.close": "xmark",
        "cmd.closecopy": "xmark",
        "cmd.closecomparison": "xmark",
        "cmd.pin": "pin",
        "cmd.panel": "sidebar.trailing",
        "cmd.newtab": "plus",
        "cmd.editjar": "slider.horizontal.3",
        "cmd.livepage": "arrow.up.right.square",
    ]
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
        if workbench.pageInFront != nil {
            rows.append(PaletteRow(id: "cmd.capture", kind: .command, title: "Capture this page",
                                   subtitle: "Into Brine", shortcut: "⌘D") { workbench.captureActivePage() })
            rows.append(PaletteRow(id: "cmd.seal", kind: .command, title: "Seal this page",
                                   subtitle: "Into the jar, frozen", shortcut: "⌘S") {
                Task { await workbench.sealActiveTab() }
            })
            rows.append(PaletteRow(id: "cmd.reader", kind: .command,
                                   title: workbench.isReading ? "Back to the page" : "Reader view",
                                   subtitle: workbench.isReading ? nil : "The article alone, in clean type",
                                   shortcut: "⌘⇧R") { Task { await workbench.toggleReader() } })
            if !workbench.isReading {
                rows.append(PaletteRow(id: "cmd.fill", kind: .command, title: "Fill this form",
                                       subtitle: "From your card", shortcut: "⌘⇧F") { workbench.fillFromMe() })
            }
            rows.append(PaletteRow(id: "cmd.close", kind: .command, title: "Close Tab", shortcut: "⌘W") { workbench.closeActiveTab() })
            let pinned = workbench.pageInFront?.isPinned == true
            rows.append(PaletteRow(id: "cmd.pin", kind: .command, title: pinned ? "Unpin Tab" : "Pin Tab",
                                   shortcut: "⌘⇧P") { workbench.togglePinActiveTab() })
        }
        if workbench.comparison != nil {
            rows.append(PaletteRow(id: "cmd.closecomparison", kind: .command, title: "Close Comparison",
                                   shortcut: "⌘W") { workbench.closeComparison() })
        } else if let copy = workbench.savedCopy {
            if copy.url != nil {
                rows.append(PaletteRow(id: "cmd.livepage", kind: .command, title: "Open Live Page",
                                       subtitle: "In a new tab") { workbench.openLivePage(copy) })
            }
            rows.append(PaletteRow(id: "cmd.closecopy", kind: .command, title: "Close Saved Copy",
                                   shortcut: "⌘W") { workbench.closeActiveTab() })
        }
        rows.append(PaletteRow(id: "cmd.panel", kind: .command, title: workbench.showPanel ? "Hide Panel" : "Show Panel",
                               shortcut: "⌘⌥I") { workbench.showPanel.toggle() })
        if workbench.activeJar != nil {
            rows.append(PaletteRow(id: "cmd.newtab", kind: .command, title: "New Tab", shortcut: "⌘T") { _ = workbench.newTab() })
            rows.append(PaletteRow(id: "cmd.editjar", kind: .command, title: "Edit Jar", shortcut: "⌘⇧E") { workbench.requestEditActiveJar() })
        }
        return rows
    }

    static func jars(_ workbench: Workbench) -> [PaletteRow] {
        var rows = workbench.jars.map { jar in
            PaletteRow(id: "jar.\(jar.id)", kind: .jar, title: jar.name, subtitle: "Jar",
                       tint: jar.tint.flatMap(OKLCH.init)?.color, jarId: jar.id, jarTint: jar.tint) { workbench.activate(jar) }
        }
        for smart in SmartJar.allCases {
            rows.append(PaletteRow(id: "jar.\(smart.rawValue)", kind: .jar, title: smart.name, subtitle: smart.paletteSubtitle,
                                   shortcut: smart.shortcutLabel) { workbench.activate(smart) })
        }
        return rows
    }

    /// Every open tab, in any jar, whose title (or address, when it has no title) matches.
    /// An empty query offers none: the strip already shows the tabs. At most six.
    static let tabRowsShown = 6

    static func tabRows(for query: String, workbench: Workbench) -> [PaletteRow] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var scored: [(row: PaletteRow, score: Int, order: Int)] = []
        for (order, tab) in workbench.allTabs.enumerated() {
            let title = (tab.title?.isEmpty == false ? tab.title : nil) ?? tab.url ?? ""
            guard !title.isEmpty, let score = PaletteMatcher.score(title, query: query) else { continue }
            let jar = workbench.jars.first { $0.id == tab.jarId }
            let row = PaletteRow(id: "tab.\(tab.id)", kind: .tab, title: title,
                                 subtitle: workbench.jarName(for: tab.jarId),
                                 url: tab.url, jarId: jar?.id, jarTint: jar?.tint, glyph: workbench.glyph(of: tab)) { workbench.open(tab) }
            scored.append((row, score, order))
        }
        // Best first; ties keep the tabs' own order.
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(tabRowsShown).map(\.row)
    }

    /// What VoiceOver hears once typing pauses: how many rows match, and the first, which
    /// Return would run. "3 matches. Pricing, Client site"; "Nothing matches".
    static func resultsLine(count: Int, first: PaletteRow?) -> String {
        guard count > 0, let first else { return "Nothing matches" }
        return "\(count == 1 ? "1 match" : "\(count) matches"). \(first.spokenLabel)"
    }

    /// Full-text hits, newest-best first. Empty query means no search at all.
    static func pantryRows(for query: String, workbench: Workbench) -> [PaletteRow] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let items = workbench.searchPantry(query)
        return items.prefix(8).map { item in
            let jar = workbench.jars.first { $0.id == item.jarId }
            return PaletteRow(id: "item.\(item.id)", kind: .item, title: item.title.isEmpty ? (item.url ?? "Untitled") : item.title,
                              subtitle: jar?.name ?? "Brine", url: item.url, jarId: jar?.id, jarTint: jar?.tint,
                              sealed: item.state == .sealed) { workbench.open(item) }
        }
    }
}
