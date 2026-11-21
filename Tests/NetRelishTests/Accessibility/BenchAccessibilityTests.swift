import Foundation
import Pantry
import SwiftUI
import Testing
@testable import NetRelish

/// What VoiceOver hears in the address row, the bottom bar, the Panel and the Bench (P5):
/// the Brine pill's value, the Panel's label lines, the comparison read row by row and its
/// Changes rotor, and what the Bench says when it changes under you. Every line here is
/// user-facing copy, so the tests pin the exact words.
@Suite("Bench accessibility") @MainActor struct BenchAccessibilityTests {

    // MARK: The Brine pill

    @Test("The Brine pill's value is what Brine holds, with a unit, never \"sunk\"")
    func brineValue() {
        #expect(ShellText.brineValue(count: 0, fresh: 0) == "Empty")
        #expect(ShellText.brineValue(count: 1, fresh: 0) == "1 item")
        #expect(ShellText.brineValue(count: 3, fresh: 0) == "3 items")
        #expect(!ShellText.brineValue(count: 4, fresh: 2).contains("sunk"))
    }

    @Test("What landed since Brine was last open comes after the count")
    func brineFresh() {
        #expect(ShellText.brineValue(count: 1, fresh: 1) == "1 item, 1 new")
        #expect(ShellText.brineValue(count: 3, fresh: 2) == "3 items, 2 new")
    }

    // MARK: Increase Contrast

    @Test("Under Increase Contrast, soft lines become hairlines and fill-only edges get fg3")
    func contrastInk() {
        #expect(ShellInk.separator(.standard) == NRColor.hairlineSoft)
        #expect(ShellInk.separator(.increased) == NRColor.hairline)
        #expect(ShellInk.edge(.standard) == nil)
        #expect(ShellInk.edge(.increased) == NRColor.fg3)
    }

    @Test("Reader view's Increase Contrast colors are tokens: fg for fg-2, fg-3 for the hairline")
    func readerContrastIsTokens() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()   // Tests/NetRelishTests/Accessibility
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let css = try String(contentsOf: repo.appendingPathComponent("design/tokens.css"), encoding: .utf8)
        let lines = css.components(separatedBy: "\n")
        let source = ["--nr-fg-2": "--nr-fg", "--nr-hairline": "--nr-fg-3"]
        for entry in ReaderPage.increasedContrast {
            let token = try #require(source[entry.token], "\(entry.token) has no source token")
            let defs = lines.filter { $0.contains("\(token):") }
            #expect(defs.contains { $0.contains(entry.light) }, "\(entry.token) light should be \(token)")
            #expect(defs.contains { $0.contains(entry.dark) }, "\(entry.token) dark should be \(token)")
        }
        let page = ReaderPage.html(for: Extraction.Article(title: "Notes", byline: "", site: "", html: "<p>Hi</p>", wordCount: 100))
        #expect(page.contains("@media (prefers-contrast: more)"))
    }

    // MARK: The Panel

    @Test("Adding and removing a label is said with the label's name")
    func labelLines() {
        #expect(PanelText.labelAdded("Billing") == "Added the label Billing")
        #expect(PanelText.labelRemoved("Q4") == "Removed the label Q4")
    }

    @Test("A subtitle's middle dots are spoken as commas")
    func spokenList() {
        #expect(PanelText.spokenList("3 changes · example.com") == "3 changes, example.com")
        #expect(PanelText.spokenList("3 tabs · 12 kept · Sinks in 2 days") == "3 tabs, 12 kept, Sinks in 2 days")
        #expect(PanelText.spokenList("example.com") == "example.com")
    }

    @Test("The Bench's own lines")
    func benchLines() {
        #expect(BenchText.readerOpened == "Reader view")
        #expect(BenchText.readerClosed == "Back to the page")
        #expect(BenchText.brokenSeal
                == "This saved copy has changed since it was sealed. It no longer matches its fingerprint.")
    }

    // MARK: The comparison, row by row

    @Test("An unchanged row is read once, not once per column")
    func unchangedRow() throws {
        let diff = PageDiff(old: "One. Two is new. Three.", new: "One. Two is new. Three.")
        let row = try #require(diff.rows.first)
        #expect(ComparisonText.spokenRow(row) == "One.")
    }

    @Test("A sentence only one seal has is read as added or removed")
    func addedAndRemovedRows() throws {
        let added = try #require(PageDiff(old: "One. Three.", new: "One. Two is new. Three.").rows.first { $0.old == nil })
        #expect(ComparisonText.spokenRow(added) == "Added: Two is new.")
        let removed = try #require(PageDiff(old: "One. Two is gone. Three.", new: "One. Three.").rows.first { $0.new == nil })
        #expect(ComparisonText.spokenRow(removed) == "Removed: Two is gone.")
    }

    @Test("A changed sentence is read before and after, with the words that changed marked")
    func changedRow() throws {
        let diff = PageDiff(old: "Pro costs $29/mo. Support is by email.", new: "Pro costs $39/mo. Support is by email.")
        let row = try #require(diff.rows.first)
        #expect(ComparisonText.spokenRow(row)
                == "Changed. Before: Pro costs Removed: $29/mo. After: Pro costs Added: $39/mo.")
    }

    // MARK: The Changes rotor

    @Test("A rotor entry says what kind of change, then what the sentence says")
    func rotorLabels() throws {
        let added = try #require(PageDiff(old: "One. Three.", new: "One. Two is new. Three.").rows.first { $0.old == nil })
        #expect(ComparisonText.rotorLabel(added) == "Added: Two is new.")
        let removed = try #require(PageDiff(old: "One. Two is gone. Three.", new: "One. Three.").rows.first { $0.new == nil })
        #expect(ComparisonText.rotorLabel(removed) == "Removed: Two is gone.")
        let changed = try #require(PageDiff(old: "Pro costs $29/mo. Support is by email.",
                                            new: "Pro costs $39/mo. Support is by email.").rows.first)
        #expect(ComparisonText.rotorLabel(changed) == "Changed: Pro costs $39/mo.")
    }

    @Test("A long change is cut short in the rotor, and says so")
    func rotorCut() throws {
        let long = "This sentence keeps going well past the point where a rotor entry stops being useful to hear"
        let row = try #require(PageDiff(old: "One. Three.", new: "One. \(long). Three.").rows.first { $0.old == nil })
        let cut = String("\(long).".prefix(ComparisonText.rotorLength)).trimmingCharacters(in: .whitespaces)
        #expect(ComparisonText.rotorLabel(row) == "Added: \(cut)…")
    }

    // MARK: What the comparison says when it's worked out

    private func comparison(_ old: String, _ new: String, diffed: Bool = true) -> Workbench.Comparison {
        let older = Item(body: old, state: .sealed, title: "Pricing", url: "https://example.com/pricing")
        let newer = Item(body: new, state: .sealed, title: "Pricing", url: "https://example.com/pricing")
        return Workbench.Comparison(older: older, newer: newer, diff: diffed ? PageDiff(old: old, new: new) : nil)
    }

    @Test("Nothing is said while the comparison is still being worked out")
    func announcementWaits() {
        #expect(ComparisonText.announcement(comparison("One.", "Two.", diffed: false)) == nil)
    }

    @Test("Once it's worked out, the comparison says how many changes, or that nothing changed")
    func announcementCounts() {
        #expect(ComparisonText.announcement(comparison("One. Three.", "One. Three.")) == ComparisonText.unchanged)
        #expect(ComparisonText.announcement(comparison("One. Three.", "One. Two is new. Three.")) == "1 change")
        #expect(ComparisonText.announcement(comparison("One. Three.", "Zero. One. Two. Three.")) == "2 changes")
    }

    @Test("Seals with no article text say so, as the note does")
    func announcementNoText() {
        #expect(ComparisonText.announcement(comparison("", "", diffed: false)) == ComparisonText.noText)
    }

    @Test("The address field says whether the page in front is on a secure connection")
    func connectionHint() {
        #expect(ShellText.connectionHint(hasPage: true, scheme: "https") == "Secure connection.")
        #expect(ShellText.connectionHint(hasPage: true, scheme: "HTTPS") == "Secure connection.")
        #expect(ShellText.connectionHint(hasPage: true, scheme: "http") == "Not a secure connection.")
        #expect(ShellText.connectionHint(hasPage: true, scheme: nil) == "Not a secure connection.")
        #expect(ShellText.connectionHint(hasPage: false, scheme: "https") == "")
    }
}
