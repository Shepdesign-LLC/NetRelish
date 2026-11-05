import Foundation
import GRDB
import Testing
@testable import Pantry

/// A summarizer that answers from a script and remembers what it was handed.
private actor StandInSummarizer: Summarizer {
    var readinessAnswer: SummarizerReadiness
    var answer: Result<String, Error>
    private(set) var handed: [SealedText] = []

    init(_ readiness: SummarizerReadiness = .ready, answer: Result<String, Error> = .success("A short summary.")) {
        self.readinessAnswer = readiness
        self.answer = answer
    }

    func set(_ readiness: SummarizerReadiness) { readinessAnswer = readiness }
    func respond(with next: Result<String, Error>) { answer = next }
    func readiness() async -> SummarizerReadiness { readinessAnswer }
    func summarize(_ page: SealedText) async throws -> String {
        handed.append(page)
        return try answer.get()
    }
}

private struct ModelGaveUp: Error {}

@Suite("Seal & Summarize") struct SummaryTests {

    private func store() throws -> PantryStore { try PantryStore(inMemory: ()) }

    /// Seals a page into Read Later, a seeded jar, which V2 gives Seal & Summarize.
    private func seal(_ store: PantryStore, body: String? = "The client agreed to net thirty with a pumpernickel clause.",
                      jarId: String = "read-later") throws -> Item {
        try store.write { db in
            try store.sealPage(db, url: "https://example.com/terms", title: "Invoice terms", body: body,
                               excerpt: nil, archive: Data("ARCHIVE".utf8), jarId: jarId, source: .browse)
        }
    }

    private func reread(_ item: Item, in store: PantryStore) throws -> Item {
        try #require(try store.read { db in try Item.fetchOne(db, key: item.id) })
    }

    @Test("V2 gives Seal & Summarize its summarize step and makes it every seeded jar's default")
    func migration() throws {
        let store = try store()
        let (jars, steps) = try store.read { db in
            (try Jar.fetchAll(db), try Recipe.fetchOne(db, key: PantryStore.sealAndSummarizeRecipeId)!.steps(db))
        }
        #expect(!jars.isEmpty)
        #expect(jars.allSatisfy { $0.defaultRecipeId == PantryStore.sealAndSummarizeRecipeId })
        #expect(steps.map(\.action) == [.summarize])
    }

    @Test("Sealing into a jar with Seal & Summarize leaves the page waiting for a summary")
    func sealingAsksForASummary() throws {
        let store = try store()
        let item = try seal(store)
        let (state, waiting) = try store.read { db in
            (try store.summaryState(db, of: item.id), try store.awaitingSummary(db).map(\.id))
        }
        #expect(state == .pending)
        #expect(waiting == [item.id])
        #expect(try reread(item, in: store).storedSummary == nil, "pending is worked out, never stored")
    }

    @Test("A jar with no default Recipe asks for no summary")
    func noRecipeNoSummary() throws {
        let store = try store()
        let plain = try store.write { db in
            var jar = Jar(name: "Plain", sortOrder: 9)
            try jar.insert(db)
            return jar
        }
        let item = try seal(store, jarId: plain.id)
        #expect(try store.read { db in try store.summaryState(db, of: item.id) } == nil)
        #expect(try store.read { db in try store.awaitingSummary(db) }.isEmpty)
    }

    @Test("The worker writes the summary from the sealed text, and nothing waits after")
    func writesTheSummary() async throws {
        let store = try store()
        let item = try seal(store)
        let model = StandInSummarizer(answer: .success("Net thirty, with a pumpernickel clause."))
        let changed = await SummaryWorker(store: store, summarizer: model).sweep()

        #expect(changed == [item.id])
        let after = try reread(item, in: store)
        #expect(after.storedSummary == .done("Net thirty, with a pumpernickel clause."))
        #expect(after.body == item.body && after.snapshotPath == item.snapshotPath && after.sealedAt == item.sealedAt,
                "the sealed snapshot is untouched")
        #expect(try store.read { db in try store.awaitingSummary(db) }.isEmpty)

        let handed = await model.handed
        #expect(handed.count == 1)
        #expect(handed.first?.text == item.body, "the model reads the text frozen at Seal, nothing else")
    }

    @Test("A page with no article text is marked so, and the model is never asked")
    func noText() async throws {
        let store = try store()
        let item = try seal(store, body: nil)
        let model = StandInSummarizer()
        await SummaryWorker(store: store, summarizer: model).sweep()
        #expect(try reread(item, in: store).storedSummary == .noText)
        #expect(await model.handed.isEmpty)
    }

    @Test("With Apple Intelligence off, the page says so, and gets its summary once it's on")
    func unavailableThenReady() async throws {
        let store = try store()
        let item = try seal(store)
        let model = StandInSummarizer(.unavailable(.appleIntelligenceOff))
        let worker = SummaryWorker(store: store, summarizer: model)

        await worker.sweep()
        #expect(try reread(item, in: store).storedSummary == .unavailable(.appleIntelligenceOff))
        #expect(await model.handed.isEmpty)

        await model.set(.ready)
        await worker.sweep()
        #expect(try reread(item, in: store).storedSummary == .done("A short summary."))
    }

    @Test("While the model is still getting ready, nothing is written and the page keeps waiting")
    func notYet() async throws {
        let store = try store()
        let item = try seal(store)
        let changed = await SummaryWorker(store: store, summarizer: StandInSummarizer(.notYet)).sweep()
        #expect(changed.isEmpty)
        #expect(try store.read { db in try store.summaryState(db, of: item.id) } == .pending)
    }

    @Test("A model that keeps failing gets three tries, then the page is marked failed for good")
    func failed() async throws {
        let store = try store()
        let item = try seal(store)
        let model = StandInSummarizer(answer: .failure(ModelGaveUp()))
        let worker = SummaryWorker(store: store, summarizer: model)

        await worker.sweep()
        #expect(try reread(item, in: store).storedSummary == .retrying(attempts: 1))
        #expect(try store.read { db in try store.awaitingSummary(db) }.map(\.id) == [item.id], "still waiting")
        await worker.sweep()
        await worker.sweep()
        #expect(try reread(item, in: store).storedSummary == .failed)
        await worker.sweep()
        #expect(await model.handed.count == SummaryState.maxAttempts, "a failed page isn't tried again")
    }

    @Test("A passing failure (the model was busy) is tried again, and the summary lands")
    func busyThenFine() async throws {
        let store = try store()
        let item = try seal(store)
        let model = StandInSummarizer(answer: .failure(ModelGaveUp()))
        let worker = SummaryWorker(store: store, summarizer: model)
        await worker.sweep()
        await model.respond(with: .success("Net thirty."))
        await worker.sweep()
        #expect(try reread(item, in: store).storedSummary == .done("Net thirty."))
    }

    @Test("Sweeps that overlap summarize each page once")
    func overlappingSweeps() async throws {
        let store = try store()
        _ = try seal(store)
        let model = StandInSummarizer()
        let worker = SummaryWorker(store: store, summarizer: model)
        async let a = worker.sweep()
        async let b = worker.sweep()
        _ = await (a, b)
        #expect(await model.handed.count == 1)
    }

    @Test("Only a sealed page has text a summarizer may read")
    func sealedTextIsSealedOnly() throws {
        let store = try store()
        let captured = try store.write { db in try store.capture(db, url: "https://example.com/live", source: .browse) }
        var withBody = captured
        withBody.body = "Text on a page that was never sealed."
        #expect(SealedText(withBody) == nil)
        #expect(SealedText(try seal(store)) != nil)
    }

    @Test("Long article text is cut to the limit at a whole word")
    func trimming() throws {
        let words = Array(repeating: "pumpernickel", count: 1_000).joined(separator: " ")
        let cut = SealedText.trim(words, to: SealedText.characterLimit)
        #expect(cut.count <= SealedText.characterLimit)
        #expect(cut.hasSuffix("pumpernickel"))
        #expect(SealedText.trim("short", to: 100) == "short")
    }

    @Test("A summary sits in meta beside what's already there, and pending clears it")
    func metaKeepsOtherKeys() throws {
        var item = Item(meta: try JSONSerialization.data(withJSONObject: ["originJar": "read-later"]))
        item.setStoredSummary(.done("Hello."))
        #expect(item.storedSummary == .done("Hello."))
        #expect(item.sunkOriginJarId == "read-later")
        item.setStoredSummary(.pending)
        #expect(item.storedSummary == nil)
        #expect(item.sunkOriginJarId == "read-later")
    }

    @Test("Shortcuts gets the summary with the item")
    func shortcutsSeeTheSummary() async throws {
        let store = try store()
        let item = try seal(store)
        await SummaryWorker(store: store, summarizer: StandInSummarizer(answer: .success("Net thirty."))).sweep()
        let entity = try #require(try PantryItemQuery.items(in: store, ids: [item.id]).first)
        #expect(entity.summary == "Net thirty.")
    }
}
