// ProvenanceWorker.swift — fingerprints every sealed page, and timestamps the fingerprint.
// Seal stays instant: this runs afterwards, off the main thread, the same way summaries do.
//
// Nothing is queued in memory: what's waiting is a question the Pantry answers
// (`awaitingProvenance`), so a page sealed just before quitting is stamped at next launch.

import Foundation

/// Somewhere that grants RFC 3161 timestamps. The app's sends the request to the authority
/// and checks the signature on the token it gets back; tests pass a stand-in.
public protocol TimestampAuthority: Sendable {
    /// The authority's host, recorded with each stamp ("timestamp.digicert.com").
    var name: String { get }
    /// Sends `request` and returns the authority's reply, its signature already checked.
    func timestamp(_ request: TimestampRequest) async throws -> Data
}

/// The authority couldn't be reached. Passing: nothing is counted against the page.
public struct TimestampUnreachable: Error {
    public init() {}
}

public actor ProvenanceWorker {
    private let store: PantryStore
    private var authority: (any TimestampAuthority)?
    private let nonce: @Sendable () -> [UInt8]
    private var running: Task<[String], Never>?
    private var again = false

    /// With no authority (none set up in this build, or not Pro), pages are fingerprinted only.
    public init(store: PantryStore, authority: (any TimestampAuthority)?) {
        self.init(store: store, authority: authority, nonce: { TimestampRequest.randomNonce() })
    }

    /// Tests fix the nonce, so a recorded reply answers the request.
    init(store: PantryStore, authority: (any TimestampAuthority)?, nonce: @escaping @Sendable () -> [UInt8]) {
        self.store = store
        self.authority = authority
        self.nonce = nonce
    }

    /// Gives or takes away the authority, as Pro unlocks or lapses (ADR 0023). A sweep
    /// already running picks it up from its next page, since each page reads it afresh.
    public func set(authority newAuthority: (any TimestampAuthority)?) {
        authority = newAuthority
    }

    /// Fingerprints and stamps every sealed page that's waiting, and returns the ids whose
    /// provenance changed. Calls that arrive mid-sweep join it, and it goes round once more.
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
            if !again || Task.isCancelled {
                running = nil
                return changed
            }
        }
    }

    private func pass() async -> [String] {
        let stamping = authority != nil
        guard let waiting = try? store.read({ db in try store.awaitingProvenance(db, stamping: stamping) }),
              !waiting.isEmpty else { return [] }
        var changed: [String] = []
        func note(_ id: String) { if changed.last != id { changed.append(id) } }   // once per page
        for item in waiting {
            if Task.isCancelled { break }
            var provenance: Provenance
            if let stored = item.provenance {
                provenance = stored
            } else {
                guard let fingerprint = try? store.fingerprint(of: item) else { continue }   // no saved copy on disk
                provenance = Provenance(fingerprint: fingerprint)
                if record(provenance, item.id) { note(item.id) }
            }
            // A fingerprint that isn't 32 bytes can't be stamped; leave it rather than stop.
            guard let authority, provenance.status == .fingerprinted, provenance.digest.count == 32 else { continue }
            let request = TimestampRequest(digest: provenance.digest, nonce: nonce())
            do {
                let reply = try await authority.timestamp(request)
                provenance.timestamp = try Timestamp(response: reply, for: request)
                provenance.status = .stamped
                provenance.authority = authority.name
            } catch is CancellationError {
                return changed
            } catch is TimestampUnreachable {
                return changed   // offline: everything waits for the next sweep, uncounted
            } catch {
                provenance = ProvenanceWorker.afterFailure(provenance)
                if record(provenance, item.id) { note(item.id) }
                return changed   // the rest wait for the next sweep
            }
            if record(provenance, item.id) { note(item.id) }
        }
        return changed
    }

    /// What a failed request turns a page's provenance into: another try, until the last.
    static func afterFailure(_ provenance: Provenance) -> Provenance {
        var next = provenance
        next.attempts += 1
        if next.attempts >= Provenance.maxAttempts { next.status = .failed }
        return next
    }

    private func record(_ provenance: Provenance, _ itemId: String) -> Bool {
        (try? store.write { db in try store.recordProvenance(db, provenance, for: itemId) }) ?? false
    }
}
