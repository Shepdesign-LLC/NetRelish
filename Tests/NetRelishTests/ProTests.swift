import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import NetRelish
@testable import Pantry

/// The decision alone: which purchase histories unlock Pro. No StoreKit involved.
@Suite("Pro: what unlocks it") @MainActor struct ProStoreTests {

    private func entitlement(_ plan: ProPlan, revoked: Bool = false, expires: Date? = nil) -> ProEntitlement {
        ProEntitlement(productID: plan.rawValue, revoked: revoked, expires: expires)
    }

    @Test("Lifetime unlocks, and wins over Annual")
    func lifetime() {
        let store = ProStore(unlocked: false)
        let soon = Date(timeIntervalSinceNow: 3_600)
        store.apply([entitlement(.annual, expires: soon), entitlement(.lifetime)], now: Date())
        #expect(store.isUnlocked)
        #expect(store.plan == .lifetime)
        #expect(store.renews == nil, "Lifetime doesn't renew")
    }

    @Test("Annual unlocks while it's active, and says when it renews")
    func annual() {
        let store = ProStore(unlocked: false)
        let renews = Date(timeIntervalSinceNow: 86_400)
        store.apply([entitlement(.annual, expires: renews)], now: Date())
        #expect(store.isUnlocked)
        #expect(store.plan == .annual)
        #expect(store.renews == renews)
    }

    @Test("An expired year, a refund, or a product we don't know never unlocks")
    func locked() {
        let store = ProStore(unlocked: false)
        let now = Date()
        store.apply([entitlement(.annual, expires: now.addingTimeInterval(-1))], now: now)
        #expect(!store.isUnlocked)
        store.apply([entitlement(.lifetime, revoked: true)], now: now)
        #expect(!store.isUnlocked)
        store.apply([ProEntitlement(productID: "com.example.other", revoked: false, expires: nil)], now: now)
        #expect(!store.isUnlocked)
        #expect(store.plan == nil)
    }

    @Test("onChange fires when Pro flips, not on every refresh")
    func onChange() {
        let store = ProStore(unlocked: false)
        var told = 0
        store.onChange = { told += 1 }
        let soon = Date(timeIntervalSinceNow: 3_600)
        store.apply([entitlement(.lifetime)], now: Date())
        store.apply([entitlement(.lifetime), entitlement(.annual, expires: soon)], now: Date())   // still unlocked
        store.apply([], now: Date())                                                              // refunded away
        #expect(told == 2)
        #expect(!store.isUnlocked)
    }

    @Test("The words: prices on the buttons, the unlocked line, no banned words")
    func words() {
        let annual = ProOffer(plan: .annual, price: "$39.00")
        let lifetime = ProOffer(plan: .lifetime, price: "$99.00")
        #expect(ProText.buy(annual) == "Buy Pro Annual, $39.00 a year")
        #expect(ProText.buy(lifetime) == "Buy Pro Lifetime, $99.00")
        #expect(ProText.lifetimeLine == "Buy once, use forever.")
        #expect(ProText.unlocked(plan: .lifetime, renews: nil) == "You have Pro Lifetime.")
        #expect(ProText.unlocked(plan: nil, renews: nil) == "Pro is unlocked in this build.")
        let renews = Date(timeIntervalSince1970: 1_825_000_000)
        #expect(ProText.unlocked(plan: .annual, renews: renews).hasPrefix("You have Pro Annual. It renews "))
    }

    @Test("A locked Pro feature opens the Pro sheet and does nothing else")
    func lockedOpensSheet() async throws {
        let bench = Workbench(store: try PantryStore(), pro: ProStore(unlocked: false))
        bench.newJar(name: "Meridian", tint: nil, shelfLifeDays: 3)
        let jarId = try #require(bench.activeJar?.id)
        bench.offscreenLoader = { url, _ in
            Workbench.OffscreenPage(archive: Data("W".utf8),
                                    extracted: Extraction.Result(title: "Pricing", excerpt: "", body: "Once."),
                                    url: url.absoluteString, title: "Pricing")
        }
        let item = try await bench.sealPage(at: URL(string: "https://example.com/pricing")!, into: jarId)

        await bench.resealAndCompare(item)

        #expect(bench.showingPro, "using a locked feature opens the Pro sheet")
        #expect(bench.seals(of: item).count == 1, "nothing was sealed")
        #expect(bench.comparison == nil)
        #expect(!bench.timestampsOn)

        // Buying flips it: the same action now works.
        bench.showingPro = false
        bench.pro.apply([ProEntitlement(productID: ProPlan.lifetime.rawValue, revoked: false, expires: nil)],
                        now: Date())
        await bench.resealAndCompare(item)
        #expect(!bench.showingPro)
        #expect(bench.seals(of: item).count == 2)
        bench.closeComparison()
    }
}

/// Real purchases against Apple's local test store (the catalog in Config/NetRelish.storekit):
/// nothing here reaches the network or a real Apple Account.
@Suite("Pro: buying against the local test store", .serialized) @MainActor struct ProStoreKitTests {

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "NetRelish")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// The test store settles purchases and refunds asynchronously, like the real one. Reads
    /// again, briefly, until the store agrees — the app itself hears these through
    /// Transaction.updates whenever they land.
    private func refresh(_ store: ProStore, until settled: @MainActor (ProStore) -> Bool) async {
        for _ in 0..<50 {
            await store.refresh()
            if settled(store) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        await store.refresh()
    }

    @Test("The catalog offers both plans, priced")
    func offers() async throws {
        let session = try makeSession()
        let store = ProStore.live()
        await store.loadOffers()
        #expect(store.offers.map(\.plan) == [.annual, .lifetime])
        #expect(store.offers.allSatisfy { !$0.price.isEmpty })
        _ = session
    }

    @Test("Buying Lifetime unlocks Pro; a refund locks it again")
    func buyAndRefund() async throws {
        let session = try makeSession()
        let store = ProStore.live()
        await store.refresh()
        #expect(!store.isUnlocked)

        let transaction = try await session.buyProduct(identifier: ProPlan.lifetime.rawValue)
        await refresh(store, until: { $0.isUnlocked })
        #expect(store.isUnlocked)
        #expect(store.plan == .lifetime)

        try session.refundTransaction(identifier: UInt(transaction.id))
        await refresh(store, until: { !$0.isUnlocked })
        #expect(!store.isUnlocked)
        #expect(store.plan == nil)
        _ = session
    }

    @Test("Buying Annual unlocks Pro and knows when it renews")
    func buyAnnual() async throws {
        let session = try makeSession()
        _ = try await session.buyProduct(identifier: ProPlan.annual.rawValue)
        let store = ProStore.live()
        await refresh(store, until: { $0.isUnlocked })
        #expect(store.isUnlocked)
        #expect(store.plan == .annual)
        #expect(store.renews.map { $0 > Date() } == true)
        _ = session
    }

    @Test("Restore finds this account's purchase")
    func restore() async throws {
        let session = try makeSession()
        _ = try await session.buyProduct(identifier: ProPlan.lifetime.rawValue)
        let store = ProStore.live()
        await store.restore()
        #expect(store.isUnlocked)
        #expect(store.note == ProText.restored)
        _ = session
    }
}
