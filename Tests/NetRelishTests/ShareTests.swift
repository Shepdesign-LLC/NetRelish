import Foundation
import Pantry
import Testing
@testable import NetRelish

/// The app side of the Share extension: what was shared lands in Brine on the next look.
@Suite("Share extension in the app") @MainActor struct ShareTests {

    @Test("receiveShared takes the inbox into Brine and says so")
    func receiveShared() throws {
        let suite = "com.shepdesign.netrelish.tests.workbench-share.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let inbox = try #require(ShareInbox(suiteName: suite))
        let bench = Workbench(store: try PantryStore(), inbox: inbox)
        let before = bench.brine.count

        inbox.add(SharedPage(url: "https://example.com/shared", title: "Shared from Safari"))
        bench.receiveShared()

        let brine = try bench.store.read { db in try bench.store.root(db).brine(db) }
        #expect(brine.count == before + 1)
        #expect(brine.first { $0.url == "https://example.com/shared" }?.source == .shareExtension)
        #expect(bench.today.contains { $0.url == "https://example.com/shared" })   // Today refreshed at once
        #expect(bench.fillStatus == "Shared into Brine")

        bench.receiveShared()   // nothing new: nothing added
        #expect(try bench.store.read { db in try bench.store.root(db).brine(db) }.count == before + 1)
    }

    @Test("Without an inbox (tests, or no App Group) nothing happens")
    func noInbox() throws {
        let bench = Workbench(store: try PantryStore())
        bench.receiveShared()
        #expect(bench.fillStatus == nil)
    }
}
