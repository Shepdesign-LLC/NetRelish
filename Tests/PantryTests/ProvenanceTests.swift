import Foundation
import GRDB
import Testing
@testable import Pantry

/// A real RFC 3161 exchange, made with openssl and a throwaway test authority:
/// the request NetRelish writes for `Fixture.archive` with nonce 0x0102030405060708, and the
/// signed reply (serial 0x2B, 2026-11-05 22:21:31 UTC). `openssl ts -verify` accepts it.
private enum Fixture {
    static let archive = Data("NetRelish provenance test fixture\n".utf8)
    static let fingerprint = "a1b3e0f8033c68a27e5cd17a108a0888b870c29f5cd2f6dfc51417a9ed0892e5"
    static let nonce: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    static let request = "30430201013031300d060960864801650304020105000420a1b3e0f8033c68a27e5cd17a108a0888b870c29f5cd2f6dfc51417a9ed0892e5020801020304050607080101ff"
    static let reply = Data(base64Encoded: [
        "MIIF9jADAgEAMIIF7QYJKoZIhvcNAQcCoIIF3jCCBdoCAQMxDzANBglghkgBZQMEAgEFADByBgsqhkiG9w0BCRABBKBjBGEw",
        "XwIBAQYEKgMEATAxMA0GCWCGSAFlAwQCAQUABCChs+D4Azxoon5c0XoQigiIuHDCn1zS9t/FFBep7QiS5QIBKxgPMjAyNjEx",
        "MDUyMjIxMzFaMAMCAQECCAECAwQFBgcIoIIDQjCCAz4wggImoAMCAQICFFRR4EPu6PjrTKSxUWffMABDDfyiMA0GCSqGSIb3",
        "DQEBCwUAMB4xHDAaBgNVBAMME05ldFJlbGlzaCBUZXN0IFJvb3QwHhcNMjYxMTA1MjIyMTMxWhcNMzYxMTAyMjIyMTMxWjAd",
        "MRswGQYDVQQDDBJOZXRSZWxpc2ggVGVzdCBUU0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCjqFzTGxP/gOcR",
        "RIzM5GT/byeeen0vZUltGeS/VLkYztQVqRShU6/WL/1Fcafz7GhWxLpD6c0T0QDv4Gy8p7cc4eecAGzy2YcoYM5Z01qhcxde",
        "AyboUnO1cNH9/nqK63xPa26/oI2WPE1z28pUHtW00aep+55kUts4anUsYiuVOtv72D/Sg3vAgZgpth0dwUhZKO2OAFdD1Fg7",
        "cHgsuSoVV2oTFpMpMvP4DdOCSpRu5VrJo4gB0bf1JT8K6LOItNHkOCMHV4p32qFWZn+mkOHDG8Eyk+3G8baW0SGQzKG7GvFJ",
        "7zT9U5Kg8D1rU5N4bRK+VhkvIhgK19o1+WPm/nd3AgMBAAGjdTBzMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMAkGA1UdEwQC",
        "MAAwDgYDVR0PAQH/BAQDAgeAMB0GA1UdDgQWBBQSxKs5hXNmB6JTjUJsDviN/xP8ajAfBgNVHSMEGDAWgBRn3xp4f53tJwUT",
        "6XPTuEmAc7De4zANBgkqhkiG9w0BAQsFAAOCAQEAm3Swclj6lBBESes3r5E72ZcUKrKa/PM6nBGgc2PAYcN5A3Kp5Zoc0ZUq",
        "l263vfZ8widY+TRYDM+9VIvqvq+AG/gwlyx/46uTzKEY6N4sm4uDtHiGsS19FAHB18UuqOSIqx1YyWs0bev1O1/xMcm0HXPk",
        "gQBGpldG/C46FuGN/l6heFF+MFslxeE67wGEoldpfSKMSfmy0zLfSs8HZwAf3FuR7egAvVQt9+J/7guIHC0IrKXIYAOcdu9i",
        "ymTc+qDXX4dFOhY/GoI18JMu9rQEQ4/wd/cSvBN2qax7LNMcEY2ykpUr0b7Z5UxjFuPoQvM8GWjCAxlPZ8MoVh/ASqQBzjGC",
        "AggwggIEAgEBMDYwHjEcMBoGA1UEAwwTTmV0UmVsaXNoIFRlc3QgUm9vdAIUVFHgQ+7o+OtMpLFRZ98wAEMN/KIwDQYJYIZI",
        "AWUDBAIBBQCggaQwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNjExMDUyMjIxMzFaMC8G",
        "CSqGSIb3DQEJBDEiBCBVN5akQpapDA31MCZM79dDRV4bTlFDnNOfOXxzCoKeFzA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCBD",
        "z2mXWbEQHYigroTzeY4fhx1hplOMi4t98BATdU9TdDANBgkqhkiG9w0BAQEFAASCAQCbYbpteyUF/fg3M9IH55hXrPA8w4MN",
        "TW9aaxNUC5TLubkDJjeafp6YNPbaZvKlOm4Idfbmt+jaj3OXDKyPSAyj8vfMd1aOvWysRav5eeYEOi1AfJ7OjSMKAnty1g7f",
        "i5+dSIusRLwjf0N3dRMxyl8Q5NfmnCRn/m83DP0T4L/2ftN1I9ys6SFdcwAH4fzt23KL+SEGK387BWiHeG0r7dOsyNhPOCOZ",
        "BS5XTYoHj5mNwKUYqN38pbzFai74Owk7ul/6LKhKAoejBXE0Sps9QXa89/BLZGDvrUgDB+HaYOhTREN61B9PnkDIak6My7VN",
        "UQK/Cfb70vRKl8JqwaVamHlH",
    ].joined())!
    /// PKIStatusInfo { status 2 (rejection) }, nothing else.
    static let refusal = Data([0x30, 0x05, 0x30, 0x03, 0x02, 0x01, 0x02])

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}

/// An authority that answers from a script and counts what it was asked.
private actor StandInAuthority: TimestampAuthority {
    nonisolated let name = "timestamp.test"
    var answer: Result<Data, Error>
    private(set) var asked = 0

    init(_ answer: Result<Data, Error> = .success(Fixture.reply)) { self.answer = answer }

    func respond(with next: Result<Data, Error>) { answer = next }
    func timestamp(_ request: TimestampRequest) async throws -> Data {
        asked += 1
        return try answer.get()
    }
}

private struct AuthorityDown: Error {}

@Suite("Provenance: RFC 3161") struct TimestampTests {

    @Test("The request is the DER openssl reads: SHA-256 imprint, nonce, certificate wanted")
    func request() throws {
        let request = TimestampRequest(digest: Provenance(fingerprint: Fixture.fingerprint).digest, nonce: Fixture.nonce)
        #expect(Fixture.hex(request.der) == Fixture.request)
    }

    @Test("A random nonce is eight bytes and positive as written")
    func nonce() {
        for _ in 0..<50 {
            let nonce = TimestampRequest.randomNonce()
            #expect(nonce.count == 8)
            #expect(nonce[0] != 0 && nonce[0] & 0x80 == 0)
        }
    }

    @Test("A granted reply is read: its time, its serial, and the token kept whole")
    func reply() throws {
        let request = TimestampRequest(digest: Provenance(fingerprint: Fixture.fingerprint).digest, nonce: Fixture.nonce)
        let stamp = try Timestamp(response: Fixture.reply, for: request)
        #expect(stamp.time == Date(timeIntervalSince1970: 1_793_917_291))   // 2026-11-05 22:21:31 UTC
        #expect(stamp.serial == "2B")
        #expect(Fixture.reply.count - stamp.token.count == 9, "the reply is the status plus the token")
        #expect(try Timestamp.digest(in: stamp.token) == request.digest)
        #expect(try Timestamp(token: stamp.token) == stamp, "a stored token reads back the same")
    }

    @Test("A reply for another fingerprint or another nonce is refused")
    func mismatch() throws {
        let otherNonce = TimestampRequest(digest: Provenance(fingerprint: Fixture.fingerprint).digest, nonce: [0x01, 0x09])
        #expect(throws: TimestampError.doesNotMatch) { try Timestamp(response: Fixture.reply, for: otherNonce) }
        let otherPage = TimestampRequest(digest: [UInt8](repeating: 7, count: 32), nonce: Fixture.nonce)
        #expect(throws: TimestampError.doesNotMatch) { try Timestamp(response: Fixture.reply, for: otherPage) }
    }

    @Test("A refusal says so, and junk is malformed")
    func refusalAndJunk() throws {
        let request = TimestampRequest(digest: Provenance(fingerprint: Fixture.fingerprint).digest, nonce: Fixture.nonce)
        #expect(throws: TimestampError.refused(status: 2)) { try Timestamp(response: Fixture.refusal, for: request) }
        #expect(throws: TimestampError.malformed) { try Timestamp(response: Data("<html>".utf8), for: request) }
        #expect(throws: TimestampError.malformed) { try Timestamp(response: Fixture.reply.prefix(200), for: request) }
    }

    @Test("GeneralizedTime with and without fractions of a second")
    func generalizedTime() throws {
        let plain = DER.Element(tag: DER.generalizedTime, value: Array("20261105222131Z".utf8), raw: [])
        let fraction = DER.Element(tag: DER.generalizedTime, value: Array("20261105222131.5Z".utf8), raw: [])
        #expect(try DER.generalizedTime(plain) == Date(timeIntervalSince1970: 1_793_917_291))
        #expect(try DER.generalizedTime(fraction) == Date(timeIntervalSince1970: 1_793_917_291.5))
    }
}

@Suite("Provenance: fingerprint and timestamp of sealed pages") struct ProvenanceTests {

    private func seal(_ store: PantryStore, archive: Data = Fixture.archive) throws -> Item {
        try store.write { db in
            try store.sealPage(db, url: "https://example.com/pricing", title: "Pricing", body: "Pro costs $29/mo.",
                               excerpt: nil, archive: archive, jarId: "read-later", source: .browse)
        }
    }

    private func reread(_ item: Item, in store: PantryStore) throws -> Item {
        try #require(try store.read { db in try Item.fetchOne(db, key: item.id) })
    }

    @Test("The fingerprint is SHA-256 of the saved copy")
    func fingerprint() throws {
        #expect(Provenance.fingerprint(of: Fixture.archive) == Fixture.fingerprint)
        #expect(Provenance(fingerprint: Fixture.fingerprint).digest.count == 32)
    }

    @Test("A saved copy that has changed since it was sealed is told apart from one that hasn't")
    func integrity() {
        let recorded = Provenance(fingerprint: Fixture.fingerprint)
        #expect(Provenance.integrity(of: Fixture.archive, against: recorded) == .intact)

        var edited = Fixture.archive
        edited[edited.startIndex] ^= 0x01                      // one bit of the page
        #expect(Provenance.integrity(of: edited, against: recorded) == .broken)
        #expect(Provenance.integrity(of: Fixture.archive + Data([0]), against: recorded) == .broken)
        #expect(Provenance.integrity(of: Data(), against: recorded) == .broken)

        #expect(Provenance.integrity(of: Fixture.archive, against: nil) == .unchecked)   // not fingerprinted yet
    }

    @Test("Without an authority a sealed page is fingerprinted, and nothing else is asked")
    func fingerprintOnly() async throws {
        let store = try PantryStore(inMemory: ())
        let item = try seal(store)
        let changed = await ProvenanceWorker(store: store, authority: nil).sweep()
        #expect(changed == [item.id])
        let provenance = try #require(try reread(item, in: store).provenance)
        #expect(provenance.fingerprint == Fixture.fingerprint)
        #expect(provenance.status == .fingerprinted)
        #expect(provenance.timestamp == nil)
        #expect(await ProvenanceWorker(store: store, authority: nil).sweep().isEmpty, "nothing left to do")
    }

    @Test("With an authority the fingerprint is timestamped, and the seal itself is untouched")
    func stamped() async throws {
        let store = try PantryStore(inMemory: ())
        let item = try seal(store)
        let authority = StandInAuthority()
        let worker = ProvenanceWorker(store: store, authority: authority, nonce: { Fixture.nonce })
        #expect(await worker.sweep() == [item.id])
        let after = try reread(item, in: store)
        let provenance = try #require(after.provenance)
        #expect(provenance.status == .stamped)
        #expect(provenance.authority == "timestamp.test")
        #expect(provenance.timestamp?.serial == "2B")
        #expect(after.sealedAt == item.sealedAt && after.body == item.body && after.snapshotPath == item.snapshotPath)
        #expect(try store.snapshots.read(try #require(after.snapshotPath)) == Fixture.archive)
        #expect(await worker.sweep().isEmpty, "a stamped page isn't asked for again")
        #expect(await authority.asked == 1)
    }

    @Test("Offline waits without counting; failures count, and the third marks it failed")
    func failures() async throws {
        let store = try PantryStore(inMemory: ())
        let item = try seal(store)
        let authority = StandInAuthority(.failure(TimestampUnreachable()))
        let worker = ProvenanceWorker(store: store, authority: authority, nonce: { Fixture.nonce })
        await worker.sweep()
        #expect(try reread(item, in: store).provenance?.attempts == 0)
        #expect(try reread(item, in: store).provenance?.status == .fingerprinted)

        await authority.respond(with: .failure(AuthorityDown()))
        await worker.sweep()
        await worker.sweep()
        #expect(try reread(item, in: store).provenance?.attempts == 2)
        #expect(try reread(item, in: store).provenance?.status == .fingerprinted)
        await worker.sweep()
        #expect(try reread(item, in: store).provenance?.status == .failed)
        #expect(await worker.sweep().isEmpty, "a failed page isn't retried on its own")
    }

    @Test("A reply for some other page is a failure, never stored as proof")
    func wrongReply() async throws {
        let store = try PantryStore(inMemory: ())
        let item = try seal(store, archive: Data("some other page".utf8))
        let worker = ProvenanceWorker(store: store, authority: StandInAuthority(), nonce: { Fixture.nonce })
        await worker.sweep()
        let provenance = try #require(try reread(item, in: store).provenance)
        #expect(provenance.timestamp == nil)
        #expect(provenance.attempts == 1)
    }

    @Test("Pages an earlier build marked failed go back to waiting, and nothing else about them changes")
    func failedPagesGetAnotherTry() async throws {
        let store = try PantryStore(inMemory: ())
        let failed = try seal(store)
        let stamped = try seal(store, archive: Data("another page".utf8))
        let request = TimestampRequest(digest: Provenance(fingerprint: Fixture.fingerprint).digest, nonce: Fixture.nonce)
        try store.write { db in
            var item = try #require(try Item.fetchOne(db, key: failed.id))
            item.setStoredSummary(.done("A short summary."))
            item.setProvenance(Provenance(fingerprint: Fixture.fingerprint, status: .failed, attempts: Provenance.maxAttempts))
            try item.update(db)
            try store.recordProvenance(db, Provenance(fingerprint: Fixture.fingerprint, status: .stamped,
                                                      timestamp: try Timestamp(response: Fixture.reply, for: request),
                                                      authority: "timestamp.example"), for: stamped.id)
        }
        let before = try reread(failed, in: store)
        #expect(try store.read { db in try store.awaitingProvenance(db, stamping: true) }.isEmpty)

        try store.write { db in try PantryMigrations.retryFailedTimestamps(db) }

        let after = try reread(failed, in: store)
        #expect(after.provenance == Provenance(fingerprint: Fixture.fingerprint))
        #expect(after.storedSummary == .done("A short summary."))
        #expect(after.sealedAt == before.sealedAt && after.body == before.body && after.snapshotPath == before.snapshotPath)
        #expect(try reread(stamped, in: store).provenance?.status == .stamped)
        #expect(try store.read { db in try store.awaitingProvenance(db, stamping: true) }.map(\.id) == [failed.id])

        // And the next sweep stamps it.
        let worker = ProvenanceWorker(store: store, authority: StandInAuthority(), nonce: { Fixture.nonce })
        #expect(await worker.sweep() == [failed.id])
        #expect(try reread(failed, in: store).provenance?.status == .stamped)
    }

    @Test("Provenance sits beside a summary in meta without disturbing it")
    func besideSummary() throws {
        var item = Item(kind: .page, state: .sealed, title: "Pricing")
        item.setStoredSummary(.done("A short summary."))
        item.setProvenance(Provenance(fingerprint: Fixture.fingerprint))
        #expect(item.storedSummary == .done("A short summary."))
        #expect(item.provenance == Provenance(fingerprint: Fixture.fingerprint))
    }
}
