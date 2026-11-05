// SummaryWorker.swift — the "Summarize" half of Seal & Summarize. Seal stays instant: the
// Recipe runs inside Seal's write and records that a summary is wanted; this worker writes it
// afterwards, off the main thread, from the sealed text alone (non-negotiable 4).
//
// Nothing is queued in memory: what's waiting is a question the Pantry answers
// (`awaitingSummary`), so a page sealed just before quitting is summarized at next launch.

import Foundation

public actor SummaryWorker {
    private let store: PantryStore
    private let summarizer: any Summarizer
    private var running: Task<[String], Never>?
    private var again = false

    public init(store: PantryStore, summarizer: any Summarizer) {
        self.store = store
        self.summarizer = summarizer
    }

    /// Summarizes every sealed page that's waiting for one, and returns the ids whose summary
    /// changed. Calls that arrive mid-sweep join it, and it goes round once more for them.
    @discardableResult
    public func sweep() async -> [String] {
        if let running {
            again = true
            return await running.value
        }
        let task = Task { await self.drain() }
        running = task
        return await task.value
    }

    private func drain() async -> [String] {
        var changed: [String] = []
        while true {
            again = false
            changed += await pass()
            // No suspension between this check and clearing `running`, so a sweep that
            // arrives later always starts a fresh pass.
            if !again || Task.isCancelled {
                running = nil
                return changed
            }
        }
    }

    private func pass() async -> [String] {
        guard let waiting = try? store.read({ db in try store.awaitingSummary(db) }), !waiting.isEmpty else { return [] }
        let readiness = await summarizer.readiness()
        var changed: [String] = []
        for item in waiting {
            if Task.isCancelled { break }
            guard let page = SealedText(item) else {
                if record(.noText, item.id) { changed.append(item.id) }
                continue
            }
            switch readiness {
            case .notYet:
                return changed   // still waiting; tried again on the next seal or launch
            case .unavailable(let why):
                if record(.unavailable(why), item.id) { changed.append(item.id) }
            case .ready:
                let state: SummaryState
                do {
                    let text = try await summarizer.summarize(page)
                    state = text.isEmpty ? .failed : .done(text)
                } catch is CancellationError {
                    return changed
                } catch {
                    state = .failed
                }
                if record(state, item.id) { changed.append(item.id) }
            }
        }
        return changed
    }

    private func record(_ state: SummaryState, _ itemId: String) -> Bool {
        (try? store.write { db in try store.recordSummary(db, state, for: itemId) }) ?? false
    }
}
