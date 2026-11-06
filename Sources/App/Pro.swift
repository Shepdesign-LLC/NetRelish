// Pro.swift — whether NetRelish Pro is unlocked, and buying it (ADR 0003, ADR 0023).
//
// One place decides: `ProStore.isUnlocked`. In the App Store build it reads StoreKit 2's
// verified record of what this Apple Account bought: Pro Lifetime, or Pro Annual while it's
// active, never one that was refunded. The Direct build stays unlocked until its license key
// lands (ADR 0007). Nothing here talks to anything but StoreKit (non-negotiable 5).

import Foundation
import Observation
import StoreKit
import SwiftUI
import os

/// The two ways to buy Pro. The raw values are the App Store Connect product IDs.
enum ProPlan: String, CaseIterable, Sendable {
    case annual = "com.shepdesign.netrelish.pro.annual"
    case lifetime = "com.shepdesign.netrelish.pro.lifetime"

    var name: String {
        switch self {
        case .annual: "Pro Annual"
        case .lifetime: "Pro Lifetime"
        }
    }
}

/// What StoreKit says about one purchase, reduced to what decides Pro.
struct ProEntitlement: Equatable, Sendable {
    let productID: String
    let revoked: Bool
    let expires: Date?
}

/// A plan as the Pro window shows it: its price as the App Store formats it for this person.
struct ProOffer: Equatable, Sendable, Identifiable {
    let plan: ProPlan
    let price: String
    var id: ProPlan { plan }
}

@MainActor
@Observable
final class ProStore {
    private(set) var isUnlocked: Bool
    /// Which plan unlocked Pro, when StoreKit says so. Nil in the Direct build.
    private(set) var plan: ProPlan?
    /// When Pro Annual renews or ends.
    private(set) var renews: Date?
    /// The plans with the App Store's prices, once loaded.
    private(set) var offers: [ProOffer] = []
    private(set) var busy = false
    /// The last thing to tell the person, in a sentence.
    private(set) var note: String?

    /// Told whenever `isUnlocked` changes, so stamping can start or stop.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var products: [ProPlan: Product] = [:]
    @ObservationIgnored private var updates: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.shepdesign.netrelish", category: "pro")

    /// A fixed answer: the Direct build until its license key exists, tests, and snapshots
    /// (which pass `offers` so the sheet has prices to show).
    init(unlocked: Bool, offers: [ProOffer] = []) {
        live = false
        isUnlocked = unlocked
        self.offers = offers
    }

    /// StoreKit's answer, kept current while the app runs.
    private init(live: Void) {
        self.live = true
        isUnlocked = false
    }

    static func live() -> ProStore {
        let store = ProStore(live: ())
        store.start()
        return store
    }

    private func start() {
        // Purchases made elsewhere (another Mac, a renewal, a refund) arrive here.
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadOffers()
        }
    }

    // MARK: What's unlocked

    /// Reads every current entitlement StoreKit has verified, and decides.
    func refresh() async {
        guard live else { return }
        var entitlements: [ProEntitlement] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }   // unverified never unlocks
            entitlements.append(ProEntitlement(productID: transaction.productID,
                                               revoked: transaction.revocationDate != nil,
                                               expires: transaction.expirationDate))
        }
        apply(entitlements, now: Date())
    }

    /// The decision itself, kept apart from StoreKit so tests can put any history through it.
    /// Lifetime wins over Annual. A refunded purchase never counts; an expired one neither.
    func apply(_ entitlements: [ProEntitlement], now: Date) {
        let valid = entitlements.filter { !$0.revoked && ($0.expires.map { $0 > now } ?? true) }
        let plans = valid.compactMap { ProPlan(rawValue: $0.productID) }
        let newPlan: ProPlan? = plans.contains(.lifetime) ? .lifetime : plans.contains(.annual) ? .annual : nil
        let newRenews = newPlan == .annual
            ? valid.filter { $0.productID == ProPlan.annual.rawValue }.compactMap(\.expires).max()
            : nil
        let changed = (newPlan != nil) != isUnlocked
        plan = newPlan
        renews = newRenews
        isUnlocked = newPlan != nil
        if changed { onChange?() }
    }

    // MARK: Buying

    func loadOffers() async {
        guard live else { return }
        do {
            let found = try await Product.products(for: ProPlan.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: found.compactMap { product in
                ProPlan(rawValue: product.id).map { ($0, product) }
            })
            offers = ProPlan.allCases.compactMap { plan in
                products[plan].map { ProOffer(plan: plan, price: $0.displayPrice) }
            }
        } catch {
            ProStore.log.error("products: \(error.localizedDescription, privacy: .public)")
            note = ProText.storeUnreachable
        }
    }

    /// Buys `plan` with SwiftUI's purchase action (the system's own confirmation sheet).
    func buy(_ plan: ProPlan, with purchase: PurchaseAction) async {
        guard let product = products[plan] else {
            note = ProText.storeUnreachable
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await purchase(product)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    note = ProText.couldNotVerify
                    return
                }
                await transaction.finish()
                await refresh()
                note = isUnlocked ? ProText.thanks : nil
            case .pending:
                note = ProText.pending
            case .userCancelled:
                note = nil
            @unknown default:
                note = nil
            }
        } catch {
            ProStore.log.error("purchase: \(error.localizedDescription, privacy: .public)")
            note = ProText.purchaseFailed
        }
    }

    /// Asks the App Store for this Apple Account's purchases again.
    func restore() async {
        guard live else { return }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
        } catch {
            // Offline, or the sign-in was cancelled. Never claim the account hasn't bought
            // Pro when the App Store didn't answer (the house rule: never claim more than
            // is true). What it did already buy still unlocks.
            ProStore.log.error("restore: \(error.localizedDescription, privacy: .public)")
            await refresh()
            note = isUnlocked ? ProText.restored : ProText.storeUnreachable
            return
        }
        await refresh()
        note = isUnlocked ? ProText.restored : ProText.nothingToRestore
    }

    deinit {
        updates?.cancel()
    }
}

/// Every Pro string, kept out of the views so tests can read them.
enum ProText {
    static let title = "NetRelish Pro"
    static let lead = "Keep proof of what the web said."
    static let featureNames = ["Reseal & diff", "Provenance"]
    static let featureLines = [
        "Seal a page again and see what changed, side by side.",
        "A timestamped fingerprint on every seal, and a proof anyone can check.",
    ]
    static let lifetimeLine = "Buy once, use forever."
    static let annualLine = "Every year, until you cancel."
    static let restore = "Restore Purchases"
    static let terms = "Terms of Use"
    static let privacy = "Privacy Policy"
    static let manage = "Manage Subscription"
    static let badge = "Pro"

    static let storeUnreachable = "The App Store didn’t answer. Check your connection and try again."
    static let couldNotVerify = "The App Store couldn’t confirm that purchase. Nothing was unlocked."
    static let purchaseFailed = "The purchase didn’t go through. You weren’t charged."
    static let pending = "Your purchase is waiting for approval. Pro unlocks as soon as it’s approved."
    static let thanks = "Pro is unlocked. Thank you."
    static let restored = "Your purchase is restored. Pro is unlocked."
    static let nothingToRestore = "This Apple Account hasn’t bought Pro."

    /// What the window says once Pro is unlocked.
    static func unlocked(plan: ProPlan?, renews: Date?) -> String {
        switch plan {
        case .lifetime: return "You have Pro Lifetime."
        case .annual:
            guard let renews else { return "You have Pro Annual." }
            return "You have Pro Annual. It renews \(renews.formatted(date: .long, time: .omitted))."
        case nil: return "Pro is unlocked in this build."
        }
    }

    /// The line under a plan's name.
    static func planLine(_ plan: ProPlan) -> String {
        plan == .lifetime ? lifetimeLine : annualLine
    }

    /// The buy button's words for a plan.
    static func buy(_ offer: ProOffer) -> String {
        switch offer.plan {
        case .annual: "Buy Pro Annual, \(offer.price) a year"
        case .lifetime: "Buy Pro Lifetime, \(offer.price)"
        }
    }

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://netrelish.com/privacy")!
    static let manageURL = URL(string: "macappstores://apps.apple.com/account/subscriptions")!
}
