// Pro.swift — whether NetRelish Pro is unlocked, and buying it (ADR 0003, ADR 0023).
//
// One place decides: `ProStore.isUnlocked`. In the App Store build it reads StoreKit 2's
// verified record of what this Apple Account bought: Pro Lifetime, or Pro Annual while it's
// active, never one that was refunded. In the Direct build it reads the license key this Mac
// activated (License.swift, ADR 0027), and asks the license relay only when the person presses
// a button. The App Store build talks to nothing but StoreKit (non-negotiable 5).

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

    /// This Mac's license, in the Direct build. Nil until one is activated, and in the App Store build.
    private(set) var license: License?

    /// Told whenever `isUnlocked` changes, so stamping can start or stop.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// The Direct build's license relay and Keychain. Nil in the App Store build and in a fixed store.
    @ObservationIgnored private let licensing: (authority: any LicenseAuthority, vault: any LicenseVault)?
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Waits until a yearly license runs out. Tests pass one they can wake by hand.
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    /// Locks Pro the moment this Mac's yearly license runs out, while the app stays open.
    @ObservationIgnored private var expiryWatch: Task<Void, Never>?
    /// A build whose relay address is broken: Pro stays locked whatever the Keychain holds,
    /// and the Keychain is left as it is.
    @ObservationIgnored private let misconfigured: Bool
    /// The Keychain couldn't be read at launch, so "no license" isn't known to be true.
    @ObservationIgnored private var vaultUnread = false
    /// The name a retried activation goes by, per key, so a reply lost on the way back and the
    /// retry show up as one Mac in the store's list rather than two.
    @ObservationIgnored private var pendingNames: [String: String] = [:]

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var products: [ProPlan: Product] = [:]
    @ObservationIgnored private var updates: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.shepdesign.netrelish", category: "pro")

    /// A fixed answer: the Direct build until its license key exists, tests, and snapshots
    /// (which pass `offers` so the sheet has prices to show).
    init(unlocked: Bool, offers: [ProOffer] = []) {
        live = false
        licensing = nil
        now = { Date() }
        sleep = { try await Task.sleep(for: $0) }
        misconfigured = false
        isUnlocked = unlocked
        self.offers = offers
    }

    /// StoreKit's answer, kept current while the app runs.
    private init(live: Void) {
        self.live = true
        licensing = nil
        now = { Date() }
        sleep = { try await Task.sleep(for: $0) }
        misconfigured = false
        isUnlocked = false
    }

    /// The Direct build: unlocked by a license key this Mac activated, as the Keychain keeps
    /// it. Nothing is asked of the relay here; only the buttons ask it.
    /// `misconfigured` is a build whose relay address is broken: Pro stays locked.
    init(licensedBy authority: any LicenseAuthority, keptIn vault: any LicenseVault,
         misconfigured: Bool = false,
         now: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        live = false
        licensing = (authority, vault)
        self.misconfigured = misconfigured
        self.now = now
        self.sleep = sleep
        isUnlocked = false
        do {
            license = try vault.load()
        } catch {
            vaultUnread = true   // Activate reads it again before trusting "no license here"
            ProStore.log.error("license keychain: \(errorKind(error), privacy: .public)")
        }
        isUnlocked = !misconfigured && (license?.unlocks(at: now()) ?? false)
        watchExpiry()
    }

    /// Whether Pro here comes from a license key (the Direct build) rather than the App Store.
    var usesLicense: Bool { licensing != nil }

    /// Why this Mac's license doesn't unlock Pro, when there is one that doesn't. Nil otherwise.
    var lockedLicenseLine: String? {
        guard let license, !isUnlocked else { return nil }
        if misconfigured { return ProText.licenseUnreachable }
        if license.status == .unknown { return ProText.licenseNeedsCheck }
        // Active but locked can only mean the year ran out since the store last said so.
        return ProText.licenseNote(license.status == .active ? .expired : license.status, expires: license.expires)
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

    // MARK: The Direct build's license key (ADR 0027)

    /// Activates `typed` on this Mac. The only time a key leaves the Mac.
    func activate(_ typed: String) async {
        // One question at a time: a second press while the first is out would ask the store
        // for a second activation and lose the first one's id.
        guard let licensing, !busy else { return }
        // Read the Keychain again if it couldn't be read at launch: an activation already kept
        // there must never be written over by a new one.
        if vaultUnread {
            do {
                license = try licensing.vault.load()
                vaultUnread = false
                settle()
            } catch {
                ProStore.log.error("license keychain: \(errorKind(error), privacy: .public)")
                note = ProText.keychainUnread
                return
            }
        }
        // A license already on this Mac is checked or given back, never replaced: replacing it
        // would strand its activation in the store.
        guard license == nil else {
            note = ProText.alreadyActivated
            return
        }
        guard let key = License.normalized(typed) else {
            note = ProText.notAKey
            return
        }
        busy = true
        defer { busy = false }
        let name = pendingNames[key] ?? License.newInstanceName()
        pendingNames[key] = name
        let reply: LicenseReply
        do {
            reply = try await licensing.authority.activate(key: key, instanceName: name)
        } catch {
            note = ProText.licenseUnreachable   // the name is kept: a retry goes by the same one
            return
        }
        guard reply.status == .active || reply.status == .expired else {
            if reply.status != .unknown { pendingNames[key] = nil }
            note = ProText.licenseNote(reply.status)
            return
        }
        guard let instanceID = reply.instanceID else {
            note = ProText.licenseUnreachable   // an activation with no id isn't one
            return
        }
        pendingNames[key] = nil
        let activated = License(key: key, instanceID: instanceID, status: reply.status, expires: reply.expires, checked: now())
        do {
            try licensing.vault.save(activated)
        } catch {
            // Not kept, its id would be gone at the next launch with the activation still
            // counted in the store. Give it back now, while the id is here, and leave Pro as
            // it was: an activation that wasn't kept never unlocks.
            ProStore.log.error("license keychain: \(errorKind(error), privacy: .public)")
            let givenBack = try? await licensing.authority.deactivate(key: key, instanceID: instanceID)
            if givenBack == nil || givenBack?.status == .unknown {
                // Not given back either: hold its id for this run, locked, so Deactivate can
                // give it back once netrelish.com or the Keychain answers.
                var held = activated
                held.status = .inactive
                license = held
                settle()
            }
            note = ProText.keychainUnsaved
            return
        }
        license = activated
        settle()
        // Unlocked, the window's own line says so. Locked, say why: a year that has run out.
        note = isUnlocked ? nil : ProText.licenseNote(.expired, expires: reply.expires)
    }

    /// Asks the relay about this Mac's license again: after a renewal, say. Only when pressed.
    func checkAgain() async {
        guard let licensing, var license, !busy else { return }
        busy = true
        defer { busy = false }
        let reply: LicenseReply
        do {
            reply = try await licensing.authority.validate(key: license.key, instanceID: license.instanceID)
        } catch {
            note = ProText.licenseUnreachable
            return
        }
        // An answer that isn't one changes nothing here, as no answer doesn't.
        guard reply.status != .unknown else {
            note = ProText.licenseUnreachable
            return
        }
        // Refused on a check means this Mac's activation isn't one the store counts anymore,
        // not that the key is in use on too many Macs.
        license.status = reply.status == .rejected ? .inactive : reply.status
        license.expires = reply.expires ?? (reply.status == .active ? nil : license.expires)
        license.checked = now()
        guard keep(license) else {
            // The Keychain still holds the old answer. If the new one locks Pro, don't let the
            // old one unlock it again at the next launch: take it out.
            if !isUnlocked { try? licensing.vault.remove() }
            note = ProText.keychainUnsaved
            return
        }
        note = isUnlocked ? nil : ProText.licenseNote(license.status == .active ? .expired : license.status,
                                                      expires: license.expires)
    }

    /// Gives this Mac's activation back, so the key can be used on another Mac. The license is
    /// forgotten here once the store has answered; offline, nothing changes.
    func deactivate() async {
        guard let licensing, var license, !busy else { return }
        busy = true
        defer { busy = false }
        let reply: LicenseReply
        do {
            reply = try await licensing.authority.deactivate(key: license.key, instanceID: license.instanceID)
        } catch {
            note = ProText.licenseUnreachable
            return
        }
        // An answer that isn't one is no answer: keep the license, and its id, as offline does.
        guard reply.status != .unknown else {
            note = ProText.licenseUnreachable
            return
        }
        // Whatever else the store answered (given back, a key it no longer knows, an activation
        // it had already let go), this Mac's activation is over: forget it here too.
        do {
            try licensing.vault.remove()
        } catch {
            ProStore.log.error("license keychain: \(errorKind(error), privacy: .public)")
            // Still in the Keychain, it would unlock Pro again at the next launch. Keep it as
            // given back instead: locked, and Deactivate tries the Keychain again.
            license.status = .inactive
            license.checked = now()
            try? licensing.vault.save(license)
            self.license = license
            settle()
            note = ProText.keychainUnsaved
            return
        }
        self.license = nil
        settle()
        note = ProText.deactivated
    }

    /// Keeps `license` in the Keychain and decides again. False when the Keychain refused it:
    /// this run goes by the new answer, and the caller decides what the next launch will see.
    @discardableResult
    private func keep(_ license: License) -> Bool {
        var kept = true
        do {
            try licensing?.vault.save(license)
        } catch {
            kept = false
            ProStore.log.error("license keychain: \(errorKind(error), privacy: .public)")
        }
        self.license = license
        settle()
        return kept
    }

    /// Whether this Mac's license unlocks Pro right now. A year that has run out locks it
    /// without asking anyone; Check Again is how a renewal is found.
    func settle() {
        guard licensing != nil else { return }
        let unlocked = !misconfigured && (license?.unlocks(at: now()) ?? false)
        let changed = unlocked != isUnlocked
        isUnlocked = unlocked
        if changed { onChange?() }
        watchExpiry()
    }

    /// While a yearly license unlocks Pro, waits for its last moment and locks it then, with no
    /// call, so stamping stops on time even if the app is never quit. The wait counts time the
    /// Mac spends asleep.
    private func watchExpiry() {
        expiryWatch?.cancel()
        expiryWatch = nil
        guard isUnlocked, let expires = license?.expires else { return }
        let wait = Duration.seconds(max(0, expires.timeIntervalSince(now())))
        expiryWatch = Task { [weak self, sleep] in
            do { try await sleep(wait) } catch { return }
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    deinit {
        updates?.cancel()
        expiryWatch?.cancel()
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

    // The Direct build's license key.
    static let keyPlaceholder = "License key"
    static let activate = "Activate"
    static let checkAgain = "Check Again"
    static let deactivate = "Deactivate This Mac"
    static let buyLicense = "Buy NetRelish Pro"
    static let keyLine = "Bought Pro on netrelish.com? Paste the license key from your receipt."
    static let notAKey = "That doesn’t look like a license key. Copy it from your receipt and paste it here."
    static let licenseUnreachable = "NetRelish couldn’t get an answer from netrelish.com. Nothing changed on this Mac. Try again in a minute."
    static let licenseActive = "Pro is active on this Mac."
    static let deactivated = "You gave back this Mac’s activation. The key works on another Mac now."
    static let alreadyActivated = "This Mac already has a license. Check it again, or deactivate it first to use another key."
    static let keychainUnread = "NetRelish couldn’t read this Mac’s Keychain, so it can’t tell whether a license is already here. Nothing was sent. Try again in a moment."
    static let licenseNeedsCheck = "NetRelish needs to check this Mac’s license again. Press Check Again."
    static let keychainUnsaved = "NetRelish couldn’t save the license in this Mac’s Keychain. Nothing is lost: try again in a moment."

    /// What the window says about a key that didn't (or no longer does) unlock Pro.
    static func licenseNote(_ status: LicenseStatus, expires: Date? = nil) -> String {
        switch status {
        case .active: return licenseActive
        case .expired:
            guard let expires else { return "This license has run out. Renew it, then press Check Again." }
            return "This license ran out on \(expires.formatted(date: .long, time: .omitted)). Renew it, then press Check Again."
        case .invalid: return "That key isn’t one we know. Check it against your receipt."
        case .rejected: return "That key is already active on as many Macs as it allows. Deactivate it on one of them first."
        case .disabled: return "This license is turned off. Pro is locked."
        case .inactive: return "This Mac’s activation isn’t active anymore. Deactivate it, then activate the key again."
        case .unknown: return licenseUnreachable
        }
    }

    /// What the window says once a license unlocks Pro.
    static func licensed(_ license: License) -> String {
        guard let expires = license.expires else { return "Pro is active on this Mac." }
        return "Pro is active on this Mac until \(expires.formatted(date: .long, time: .omitted))."
    }

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
    /// Where the Direct build sends someone to buy a key.
    static let buyURL = URL(string: "https://netrelish.com/")!
    static let privacyURL = URL(string: "https://netrelish.com/privacy")!
    static let manageURL = URL(string: "macappstores://apps.apple.com/account/subscriptions")!
}
