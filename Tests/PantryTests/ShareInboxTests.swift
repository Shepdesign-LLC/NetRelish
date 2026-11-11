import Foundation
import GRDB
import Testing
@testable import Pantry

/// The Share extension's hand-off and the Pantry taking it in. Each test gets its own
/// preferences suite, removed afterwards, so nothing touches the real App Group.
@Suite("Share extension") struct ShareInboxTests {

    private func withInbox(_ body: (ShareInbox) throws -> Void) throws {
        let suite = "com.shepdesign.netrelish.tests.share.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let inbox = try #require(ShareInbox(suiteName: suite))
        try body(inbox)
    }

    @Test("Pages come out oldest first, and the inbox is empty after")
    func takeEmptiesInOrder() throws {
        try withInbox { inbox in
            let t0 = Date(timeIntervalSince1970: 1_800_000_000)
            inbox.add(SharedPage(url: "https://b.example/", title: "B", sharedAt: t0.addingTimeInterval(60)))
            inbox.add(SharedPage(url: "https://a.example/", title: "A", sharedAt: t0))
            var first: [SharedPage] = []
            inbox.take { first = $0 }
            #expect(first.map(\.title) == ["A", "B"])
            var second: [SharedPage] = []
            inbox.take { second = $0 }
            #expect(second.isEmpty)
        }
    }

    @Test("If taking in fails, the pages stay for the next try")
    func failedTakeKeepsPages() throws {
        struct Boom: Error {}
        try withInbox { inbox in
            inbox.add(SharedPage(url: "https://a.example/", title: "A"))
            #expect(throws: Boom.self) { try inbox.take { _ in throw Boom() } }
            var again: [SharedPage] = []
            inbox.take { again = $0 }
            #expect(again.map(\.url) == ["https://a.example/"])
        }
    }

    @Test("Shared pages land in Brine as page items from the Share menu")
    func receiveIntoBrine() throws {
        let store = try PantryStore(inMemory: ())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let received = try store.write { db in
            try store.receive(db, [
                SharedPage(url: "https://example.com/terms", title: "  Terms  ", sharedAt: now),
                SharedPage(url: "https://example.com/blank", title: "", sharedAt: now),
            ], now: now)
        }
        #expect(received.count == 2)
        let brine = try store.read { db in try store.root(db).brine(db) }
        let terms = try #require(brine.first { $0.url == "https://example.com/terms" })
        #expect(terms.title == "Terms")
        #expect(terms.source == .shareExtension)
        #expect(terms.kind == .page)
        #expect(terms.state == .brined)
        #expect(terms.jarId == nil)
        #expect(terms.domain == "example.com")
        let blank = try #require(brine.first { $0.url == "https://example.com/blank" })
        #expect(blank.title == "https://example.com/blank")   // no title: the URL stands in
    }

    @Test("Sharing a page already in Brine adds nothing; non-web links are skipped")
    func receiveSkipsDuplicatesAndNonWeb() throws {
        let store = try PantryStore(inMemory: ())
        let page = SharedPage(url: "https://example.com/once", title: "Once")
        _ = try store.write { db in try store.receive(db, [page]) }
        let second = try store.write { db in
            try store.receive(db, [page, page,
                                   SharedPage(url: "file:///etc/hosts", title: "Hosts"),
                                   SharedPage(url: "javascript:alert(1)", title: "Script")])
        }
        #expect(second.isEmpty)
        let count = try store.read { db in try Item.filter(Item.Columns.source == CaptureSource.shareExtension).fetchCount(db) }
        #expect(count == 1)
    }

    @Test("A shared page is announced only once it is saved, never by a write that rolls back")
    func announcedOnlyOnCommit() throws {
        struct Boom: Error {}
        let store = try PantryStore(inMemory: ())
        let url = "https://example.com/announce-\(UUID().uuidString)"   // unique: other suites capture too
        let heard = Heard()
        let token = NotificationCenter.default.addObserver(forName: NetRelish.onCapture.name, object: nil, queue: nil) { note in
            if let item = note.userInfo?["value"] as? Item, item.url == url { heard.add() }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        #expect(throws: Boom.self) {
            try store.write { db in
                _ = try store.receive(db, [SharedPage(url: url, title: "Rolled back")])
                throw Boom()
            }
        }
        #expect(heard.count == 0)
        #expect(try store.read { db in try store.item(db, url: url) } == nil)

        _ = try store.write { db in try store.receive(db, [SharedPage(url: url, title: "Kept")]) }
        #expect(heard.count == 1)
    }

    @Test("A page shared with a clock ahead of this Mac is dated now, not in the future")
    func futureShareIsClamped() throws {
        let store = try PantryStore(inMemory: ())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = try store.write { db in
            try store.receive(db, [SharedPage(url: "https://example.com/", title: "E", sharedAt: now.addingTimeInterval(3_600))], now: now)
        }.first
        #expect(item?.createdAt == now)
    }

    // MARK: The inbox isn't trusted to hold only what the extension wrote

    @Test("A share dated in another era is dated a year back at most, and Brine still opens")
    func ancientShareIsClamped() throws {
        let store = try PantryStore(inMemory: ())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ancient = Date(timeIntervalSinceReferenceDate: -1e12)   // tens of thousands of years ago
        let item = try store.write { db in
            try store.receive(db, [SharedPage(url: "https://example.com/", title: "E", sharedAt: ancient)], now: now)
        }.first
        #expect(item?.createdAt == now.addingTimeInterval(-365 * 86_400))
        // The row reads back: one bad date must not stop Brine from loading.
        let brine = try store.read { db in try store.root(db).brine(db) }
        #expect(brine.map(\.title) == ["E"])
    }

    @Test("A title longer than the extension allows is cut, and an address longer than any real one is skipped")
    func oversizeFieldsAreBounded() throws {
        let store = try PantryStore(inMemory: ())
        let received = try store.write { db in
            try store.receive(db, [
                SharedPage(url: "https://example.com/long-title", title: String(repeating: "t", count: 5_000)),
                SharedPage(url: "https://example.com/" + String(repeating: "a", count: 9_000), title: "Too long to be an address"),
            ])
        }
        #expect(received.count == 1)
        #expect(received.first?.title.count == 300)
    }

    @Test("An entry too big to be a shared page is dropped, not taken in")
    func oversizeEntryIsDropped() throws {
        try withInbox { inbox in
            inbox.add(SharedPage(url: "https://example.com/", title: String(repeating: "x", count: 20_000)))
            inbox.add(SharedPage(url: "https://ok.example/", title: "Fine"))
            var taken: [SharedPage] = []
            inbox.take { taken = $0 }
            #expect(taken.map(\.title) == ["Fine"])
            var again: [SharedPage] = []
            inbox.take { again = $0 }
            #expect(again.isEmpty)   // the oversize one is gone, not waiting
        }
    }

    @Test("Only entries named the way the extension names them are looked at")
    func foreignKeysAreIgnored() throws {
        let suite = "com.shepdesign.netrelish.tests.share.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let page = try JSONEncoder().encode(SharedPage(url: "https://planted.example/", title: "Planted"))
        defaults.set(page, forKey: "share.not-a-uuid")
        defaults.set(page, forKey: "share.")
        let inbox = try #require(ShareInbox(suiteName: suite))
        var taken: [SharedPage] = []
        inbox.take { taken = $0 }
        #expect(taken.isEmpty)
    }

    @Test("A flood is taken a batch at a time, oldest first, and the rest wait")
    func floodIsTakenInBatches() throws {
        try withInbox { inbox in
            let t0 = Date(timeIntervalSince1970: 1_800_000_000)
            for i in 0..<(ShareInbox.batchLimit + 5) {
                inbox.add(SharedPage(url: "https://example.com/\(i)", title: "\(i)", sharedAt: t0.addingTimeInterval(Double(i))))
            }
            var first: [SharedPage] = []
            inbox.take { first = $0 }
            #expect(first.count == ShareInbox.batchLimit)
            #expect(first.first?.title == "0")
            var rest: [SharedPage] = []
            inbox.take { rest = $0 }
            #expect(rest.map(\.title) == (ShareInbox.batchLimit..<(ShareInbox.batchLimit + 5)).map(String.init))
        }
    }
}

/// Counts notifications, from whatever thread posts them.
private final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func add() { lock.withLock { value += 1 } }
}
