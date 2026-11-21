import Foundation
import Pantry
import Testing
@testable import NetRelish

/// What VoiceOver hears in the tab strip and on the jar's chip (P5): a tab's short name, its
/// state and place as a value, the moves that stand in for dragging, and the spoken parts of
/// the small components the strip is built from.
@Suite("Tab strip accessibility") @MainActor struct TabStripAccessibilityTests {

    // MARK: A tab's name

    @Test("A tab is called by its title, else its site, never the whole address")
    func spokenLabel() {
        #expect(TabStrip.spokenLabel(of: Pantry.Tab(title: "Juniper Bakery", url: "https://juniperbakery.example/")) == "Juniper Bakery")
        #expect(TabStrip.spokenLabel(of: Pantry.Tab(title: "", url: "https://www.juniperbakery.example/menu?x=1")) == "juniperbakery.example")
        #expect(TabStrip.spokenLabel(of: Pantry.Tab(url: "harborsigns.example")) == "harborsigns.example")
        #expect(TabStrip.spokenLabel(of: Pantry.Tab(url: "")) == "New Tab")
        #expect(TabStrip.spokenLabel(of: Pantry.Tab(url: nil)) == "New Tab")
    }

    @Test("The drawn title still falls back to the address")
    func drawnLabelUnchanged() {
        #expect(TabStrip.label(of: Pantry.Tab(url: "https://www.juniperbakery.example/menu")) == "https://www.juniperbakery.example/menu")
        #expect(TabIcon.letter(for: Pantry.Tab(url: "https://www.juniperbakery.example/menu")) == "J")
    }

    @Test("The strip is named for its jar")
    func stripLabel() {
        #expect(TabStrip.stripLabel(jarName: "Clients") == "Clients tabs")
    }

    // MARK: A tab's value

    @Test("A tab's value carries pinned or sinking, then its place")
    func value() {
        #expect(TabChip.accessibilityValue(isPinned: true, secondsLeft: nil, position: 1, count: 5) == "pinned, 1 of 5")
        #expect(TabChip.accessibilityValue(isPinned: false, secondsLeft: 2 * 86_400, position: 3, count: 5)
                == "sinking in 2 days, 3 of 5")
        #expect(TabChip.accessibilityValue(isPinned: false, secondsLeft: nil, position: 4, count: 5) == "4 of 5")
        // A pinned tab never sinks, so it never says both.
        #expect(TabChip.accessibilityValue(isPinned: true, secondsLeft: 600, position: 2, count: 2) == "pinned, 2 of 2")
        // A tab that isn't one of the open tabs has no place to say.
        #expect(TabChip.accessibilityValue(isPinned: false, secondsLeft: nil, position: nil, count: 5) == "")
    }

    @Test("How soon a tab sinks is said in hours or days")
    func sinkingPhrase() {
        #expect(TabChip.sinkingPhrase(0) == "sinking in under an hour")
        #expect(TabChip.sinkingPhrase(3_599) == "sinking in under an hour")
        #expect(TabChip.sinkingPhrase(3_600) == "sinking in 1 hour")
        #expect(TabChip.sinkingPhrase(3_601) == "sinking in 2 hours")
        #expect(TabChip.sinkingPhrase(86_399) == "sinking in 24 hours")
        #expect(TabChip.sinkingPhrase(86_400) == "sinking in 1 day")
        #expect(TabChip.sinkingPhrase(1.4 * 86_400) == "sinking in 1 day")
        #expect(TabChip.sinkingPhrase(2.6 * 86_400) == "sinking in 3 days")
    }

    // MARK: Moving without a drag

    @Test("A tab's neighbor is one place along, and nothing past either end")
    func neighbor() {
        let ids = ["a", "b", "c"]
        #expect(TabStrip.neighbor(of: "b", in: ids, offset: -1) == "a")
        #expect(TabStrip.neighbor(of: "b", in: ids, offset: 1) == "c")
        #expect(TabStrip.neighbor(of: "a", in: ids, offset: -1) == nil)
        #expect(TabStrip.neighbor(of: "c", in: ids, offset: 1) == nil)
        #expect(TabStrip.neighbor(of: "b", in: ids, offset: 0) == nil)
        #expect(TabStrip.neighbor(of: "z", in: ids, offset: 1) == nil)
        #expect(TabStrip.movedAnnouncement(position: 2, count: 5) == "Moved, 2 of 5")
    }

    @Test("Moving onto a neighbor moves a tab exactly one place")
    func moveLeftAndRight() throws {
        let defaults = try #require(UserDefaults(suiteName: "netrelish.tests.\(UUID().uuidString)"))
        let bench = Workbench(store: try PantryStore(), defaults: defaults)
        bench.newJar(name: "Ash", tint: nil, shelfLifeDays: 3)
        let a = try #require(bench.newTab(url: "https://a.example/"))
        let b = try #require(bench.newTab(url: "https://b.example/"))
        let c = try #require(bench.newTab(url: "https://c.example/"))

        // Move Right on a: onto b, its right neighbor.
        let right = try #require(TabStrip.neighbor(of: a.id, in: bench.tabs.map(\.id), offset: 1))
        bench.moveTab(a.id, onto: right)
        #expect(bench.tabs.map(\.id) == [b.id, a.id, c.id])

        // Move Left on c: onto a, its left neighbor.
        let left = try #require(TabStrip.neighbor(of: c.id, in: bench.tabs.map(\.id), offset: -1))
        bench.moveTab(c.id, onto: left)
        #expect(bench.tabs.map(\.id) == [b.id, c.id, a.id])
    }

    // MARK: The jar's chip and the components

    @Test("The jar's chip says how full the jar is")
    func jarChipValue() {
        #expect(JarChip.accessibilityValue(tabs: 3, kept: 12) == "3 tabs, 12 kept")
        #expect(JarChip.accessibilityValue(tabs: 1, kept: 0) == "1 tab, 0 kept")
    }

    @Test("The shelf-life bar says what's left, and when it's running low")
    func shelfLifeBar() {
        #expect(NRShelfLifeBar.accessibilityValue(remaining: 0.8) == "80 percent left")
        #expect(NRShelfLifeBar.accessibilityValue(remaining: 0.15) == "15 percent left, running low")
        #expect(NRShelfLifeBar.accessibilityValue(remaining: 1.4) == "100 percent left")
        #expect(NRShelfLifeBar.accessibilityValue(remaining: 0) == "0 percent left, running low")
    }

    @Test("Every tab has a hint, so its tooltip isn't read in its place")
    func tabHint() {
        #expect(TabChip.spokenHint(isPinned: false) == "Brings the tab forward.")
        #expect(TabChip.spokenHint(isPinned: true) == "Pinned tabs never sink. Brings the tab forward.")
    }

    @Test("Moving a tab past either end says it's already there")
    func tabEndLines() {
        #expect(TabStrip.endLine(tabName: "Pricing", first: true) == "Pricing is already first.")
        #expect(TabStrip.endLine(tabName: "Pricing", first: false) == "Pricing is already last.")
    }

    @Test("The jar glyph is named for its kind")
    func jarGlyph() {
        #expect(NRJarGlyph.spokenName(of: .plain) == "Jar")
        #expect(NRJarGlyph.spokenName(of: .smart) == "Smart jar")
        #expect(NRJarGlyph.spokenName(of: .mason) == "Mason Jar")
    }
}
