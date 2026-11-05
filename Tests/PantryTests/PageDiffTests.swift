import Foundation
import GRDB
import Testing
@testable import Pantry

@Suite("Reseal & diff: the comparison") struct PageDiffTests {

    @Test("Text is cut into sentences, whitespace collapsed")
    func sentences() {
        let text = "Plans start at $29/mo.  Support is by email!\n\nWhy wait? 14-day trial. e.g. not a split."
        #expect(PageDiff.sentences(text) == [
            "Plans start at $29/mo.", "Support is by email!", "Why wait?", "14-day trial. e.g. not a split."
        ])
    }

    @Test("A long run with no punctuation is cut at a space, not mid-word")
    func longRuns() {
        let text = Array(repeating: "pumpernickel", count: 200).joined(separator: " ")
        let parts = PageDiff.sentences(text)
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= PageDiff.maxSentence + 20 })
        #expect(parts.joined(separator: " ") == text)
    }

    @Test("Two identical seals have no changes")
    func identical() {
        let diff = PageDiff(old: "Net thirty. Pumpernickel clause.", new: "Net  thirty.\nPumpernickel clause.")
        #expect(diff.isUnchanged)
        #expect(diff.rows.count == 2)
    }

    @Test("A price change is one changed row: the old price struck, the new one added")
    func priceChange() throws {
        let diff = PageDiff(old: "Pro costs $29/mo. Support is by email.",
                            new: "Pro costs $39/mo. Support is by email.")
        #expect(diff.changeCount == 1)
        let row = try #require(diff.rows.first)
        #expect(row.isChange)
        #expect(row.old == [.init("Pro costs", .same), .init("$29/mo.", .removed)])
        #expect(row.new == [.init("Pro costs", .same), .init("$39/mo.", .added)])
        #expect(diff.rows.last?.isChange == false)
    }

    @Test("An added sentence has an empty left side; a removed one, an empty right side")
    func addedAndRemoved() {
        let added = PageDiff(old: "One. Three.", new: "One. Two is new. Three.")
        #expect(added.changeCount == 1)
        #expect(added.rows.contains { $0.old == nil && $0.new == [.init("Two is new.", .added)] })

        let removed = PageDiff(old: "One. Two is gone. Three.", new: "One. Three.")
        #expect(removed.rows.contains { $0.new == nil && $0.old == [.init("Two is gone.", .removed)] })
    }

    @Test("Rows keep the page's order and every sentence from both seals")
    func completeness() {
        let old = "A one. B two. C three. D four."
        let new = "A one. B twenty. D four. E five."
        let diff = PageDiff(old: old, new: new)
        let left = diff.rows.compactMap(\.old).map { $0.map(\.text).joined(separator: " ") }
        let right = diff.rows.compactMap(\.new).map { $0.map(\.text).joined(separator: " ") }
        #expect(left == PageDiff.sentences(old))
        #expect(right == PageDiff.sentences(new))
    }

    @Test("Empty seals compare as unchanged with no rows")
    func empty() {
        #expect(PageDiff(old: "", new: "").rows.isEmpty)
    }

    @Test("A 2 MB page with a few changes is compared quickly")
    func largePage() throws {
        let paragraph = (0..<20).map { "Sentence number \($0) about plans and prices." }.joined(separator: " ")
        var old = ""
        while old.utf8.count < 2_000_000 { old += paragraph + " " }
        // One real edit, as a reseal usually finds: the first "number 7" sentence gains a word.
        var new = old
        let hit = try #require(new.range(of: "Sentence number 7 about plans"))
        new.replaceSubrange(hit, with: "Sentence number 7 about new plans")
        let clock = ContinuousClock()
        var diff: PageDiff?
        let elapsed = clock.measure { diff = PageDiff(old: old, new: new) }
        print("PageDiff 2 MB: \(elapsed)")   // the plan's budget is 1 s in a release build
        #expect(diff?.changeCount == 1)
        #expect(elapsed < .seconds(10), "a debug build is slower; this only guards against a blow-up")
    }

    @Test("A page rewritten end to end is shown removed, then added, without stalling")
    func rewrittenPage() {
        let old = (0..<8_000).map { "Old sentence \($0) here." }.joined(separator: " ")
        let new = (0..<8_000).map { "New sentence \($0) there." }.joined(separator: " ")
        let clock = ContinuousClock()
        var diff: PageDiff?
        let elapsed = clock.measure { diff = PageDiff(old: old, new: new) }
        #expect(diff?.changeCount == 16_000)
        #expect(diff?.rows.first?.new == nil && diff?.rows.last?.old == nil, "removed first, then added")
        #expect(elapsed < .seconds(10))
    }

    @Test("The same start and end stay lined up around a changed middle")
    func trimmedEnds() {
        let diff = PageDiff(old: "Intro here. Price is 29. Outro here.", new: "Intro here. Price is 39. Outro here.")
        #expect(diff.rows.count == 3)
        #expect(diff.rows.map(\.isChange) == [false, true, false])
        #expect(diff.rows.map(\.id) == [0, 1, 2])
    }
}

@Suite("Reseal & diff: a page's seals") struct ResealStoreTests {

    private func seal(_ store: PantryStore, body: String) throws -> Item {
        try store.write { db in
            try store.sealPage(db, url: "https://example.com/pricing", title: "Pricing", body: body, excerpt: nil,
                               archive: Data("A".utf8), jarId: "read-later", source: .browse)
        }
    }

    // Back-to-back seals can share a millisecond; the order must still be newest first.
    @Test("Sealing a page again keeps both seals, newest first, and the earlier one untouched")
    func seals() throws {
        let store = try PantryStore(inMemory: ())
        let first = try seal(store, body: "Pro costs $29/mo.")
        let second = try seal(store, body: "Pro costs $39/mo.")
        let seals = try store.read { db in try store.seals(db, url: "https://example.com/pricing") }
        #expect(seals.map(\.id) == [second.id, first.id])
        #expect(seals.last?.body == "Pro costs $29/mo.", "the earlier seal keeps its own text")
        #expect(try store.read { db in try store.previousSeal(db, before: second) }?.id == first.id)
        #expect(try store.read { db in try store.previousSeal(db, before: first) } == nil)
    }
}
