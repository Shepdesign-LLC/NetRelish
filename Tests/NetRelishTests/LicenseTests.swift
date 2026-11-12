import Foundation
import Testing
@testable import NetRelish

// The Direct build's license key (ADR 0027). Nothing here reaches the network: the relay is
// answered by StandInRelay, and ProStore is given a stand-in authority and vault.

// MARK: - Stand-ins

/// Answers for the license relay and remembers what it was asked.
final class StubAuthority: LicenseAuthority, @unchecked Sendable {
    enum Call: Equatable { case activate(key: String, name: String), validate(key: String, id: String), deactivate(key: String, id: String) }

    private let lock = NSLock()
    private var answer: Result<LicenseReply, any Error>
    private var made: [Call] = []
    private var deactivateFails = false

    init(_ reply: LicenseReply) { answer = .success(reply) }
    init(failing error: any Error) { answer = .failure(error) }

    func answer(with reply: LicenseReply) { lock.withLock { answer = .success(reply) } }
    func fail(with error: any Error) { lock.withLock { answer = .failure(error) } }
    /// Deactivations alone get no answer, while the rest still do.
    func failDeactivations() { lock.withLock { deactivateFails = true } }
    var calls: [Call] { lock.withLock { made } }

    private func respond(_ call: Call) throws -> LicenseReply {
        try lock.withLock {
            made.append(call)
            return try answer.get()
        }
    }

    func activate(key: String, instanceName: String) async throws -> LicenseReply { try respond(.activate(key: key, name: instanceName)) }
    func validate(key: String, instanceID: String) async throws -> LicenseReply { try respond(.validate(key: key, id: instanceID)) }
    func deactivate(key: String, instanceID: String) async throws -> LicenseReply {
        if lock.withLock({ deactivateFails }) {
            lock.withLock { made.append(.deactivate(key: key, id: instanceID)) }
            throw LicenseUnreachable()
        }
        return try respond(.deactivate(key: key, id: instanceID))
    }
}

/// An authority that holds every question until the test opens it, so a test can press a
/// button again while the first question is still out.
final class GatedAuthority: LicenseAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var count = 0

    var calls: Int { lock.withLock { count } }

    func open() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        held.forEach { $0.resume() }
    }

    private func held() async -> LicenseReply {
        lock.withLock { count += 1 }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiting.append(continuation)
                return false
            }
            if now { continuation.resume() }
        }
        return LicenseReply(status: .active, instanceID: "ins_1", expires: nil)
    }

    func activate(key: String, instanceName: String) async throws -> LicenseReply { await held() }
    func validate(key: String, instanceID: String) async throws -> LicenseReply { await held() }
    func deactivate(key: String, instanceID: String) async throws -> LicenseReply { await held() }
}

/// A Keychain in memory, which a test can make refuse to read, save or remove.
final class MemoryVault: LicenseVault, @unchecked Sendable {
    struct Refused: Error {}
    private let lock = NSLock()
    private var kept: License?
    private var refusing: (load: Bool, save: Bool, remove: Bool) = (false, false, false)
    init(_ license: License? = nil) { kept = license }
    var stored: License? { lock.withLock { kept } }
    func refuse(load: Bool = false, save: Bool = false, remove: Bool = false) {
        lock.withLock { refusing = (load, save, remove) }
    }
    func load() throws -> License? {
        try lock.withLock {
            if refusing.load { throw Refused() }
            return kept
        }
    }
    func save(_ license: License) throws {
        try lock.withLock {
            if refusing.save { throw Refused() }
            kept = license
        }
    }
    func remove() throws {
        try lock.withLock {
            if refusing.remove { throw Refused() }
            kept = nil
        }
    }
}

/// Stands in for the wait until a yearly license runs out: remembers how long it was asked
/// to wait, and returns only when the test wakes it.
@MainActor final class TestSleeper {
    private(set) var asked: [Duration] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func sleep(_ duration: Duration) async throws {
        asked.append(duration)
        await withCheckedContinuation { waiting.append($0) }
    }
    func wake() {
        let held = waiting
        waiting = []
        held.forEach { $0.resume() }
    }
}

/// A clock a test can move.
@MainActor final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(days: Double) { now = now.addingTimeInterval(days * 86_400) }
}

private let key = "NR-PRO-7F3A9C21-44B0-4E0D-A1B2"

private func reply(_ status: LicenseStatus, id: String? = "ins_123", expires: Date? = nil) -> LicenseReply {
    LicenseReply(status: status, instanceID: id, expires: expires)
}

// MARK: - The key itself

@Suite("License: the key, and what unlocks Pro") struct LicenseKeyTests {
    @Test("A pasted key is tidied: spaces and line breaks around it go")
    func tidy() {
        #expect(License.normalized("  \(key)\n") == key)
        #expect(License.normalized("\t\(key) ") == key)
    }

    @Test("Text that can't be a key is refused before anything is sent",
          arguments: ["", "short", String(repeating: "A", count: 129), "NR PRO 1234 5678", "NR-PRO-1234;rm",
                      "NR-PRO-ÄÖÜ-1234", "<script>alert(1)</script>", "key\u{0}withnul"])
    func refused(_ text: String) {
        #expect(License.normalized(text) == nil)
    }

    @Test("Each Mac gets a random name that says nothing about it")
    func instanceName() {
        let one = License.newInstanceName(), two = License.newInstanceName()
        #expect(one != two)
        #expect(one.hasPrefix("NetRelish-"))
        #expect(one.count == "NetRelish-".count + 8)
    }

    @Test("Active unlocks; a year that has run out, or any other status, doesn't")
    func unlocks() {
        let now = Date()
        func license(_ status: LicenseStatus, _ expires: Date?) -> License {
            License(key: key, instanceID: "ins", status: status, expires: expires, checked: now)
        }
        #expect(license(.active, nil).unlocks(at: now))
        #expect(license(.active, now.addingTimeInterval(60)).unlocks(at: now))
        #expect(!license(.active, now.addingTimeInterval(-60)).unlocks(at: now))
        for status in [LicenseStatus.inactive, .expired, .disabled, .invalid, .rejected, .unknown] {
            #expect(!license(status, nil).unlocks(at: now), "\(status)")
        }
    }
}

// MARK: - ProStore in the Direct build

@Suite("Pro: the Direct build's license key") @MainActor struct LicensedProTests {

    @Test("Nothing is asked of the relay at launch, with or without a license on this Mac")
    func noCallAtLaunch() {
        let stored = License(key: key, instanceID: "ins_1", status: .active, expires: nil, checked: .distantPast)
        let authority = StubAuthority(reply(.active))
        let withLicense = ProStore(licensedBy: authority, keptIn: MemoryVault(stored))
        let without = ProStore(licensedBy: authority, keptIn: MemoryVault())
        #expect(withLicense.isUnlocked, "a license this Mac already activated unlocks at launch")
        #expect(!without.isUnlocked)
        #expect(authority.calls.isEmpty)
        #expect(withLicense.usesLicense)
        #expect(!ProStore(unlocked: true).usesLicense)
    }

    @Test("A key that activates unlocks Pro and is kept in the Keychain")
    func activates() async {
        let authority = StubAuthority(reply(.active))
        let vault = MemoryVault()
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        var told = 0
        pro.onChange = { told += 1 }
        await pro.activate("  \(key)\n")
        #expect(pro.isUnlocked)
        #expect(told == 1)
        #expect(vault.stored?.key == key)
        #expect(vault.stored?.instanceID == "ins_123")
        #expect(pro.note == nil, "the window's licensed line says so; no second line")
        #expect(pro.lockedLicenseLine == nil)
        guard case .activate(let sent, let name) = authority.calls.first else {
            Issue.record("expected an activation, got \(authority.calls)")
            return
        }
        #expect(sent == key, "the tidied key, not what was pasted")
        #expect(name.hasPrefix("NetRelish-"))
    }

    @Test("Text that isn't a key is caught on the Mac, and nothing is sent")
    func notAKey() async {
        let authority = StubAuthority(reply(.active))
        let pro = ProStore(licensedBy: authority, keptIn: MemoryVault())
        await pro.activate("hello there")
        #expect(!pro.isUnlocked)
        #expect(pro.note == ProText.notAKey)
        #expect(authority.calls.isEmpty)
    }

    @Test("A key the store refuses leaves Pro locked and nothing kept",
          arguments: [LicenseStatus.invalid, .rejected, .disabled, .inactive, .unknown])
    func refused(_ status: LicenseStatus) async {
        let vault = MemoryVault()
        let pro = ProStore(licensedBy: StubAuthority(reply(status, id: status == .invalid ? nil : "ins_1")), keptIn: vault)
        await pro.activate(key)
        #expect(!pro.isUnlocked)
        #expect(vault.stored == nil)
        #expect(pro.note == ProText.licenseNote(status))
    }

    @Test("An active answer with no activation id isn't a license")
    func noInstance() async {
        let vault = MemoryVault()
        let pro = ProStore(licensedBy: StubAuthority(reply(.active, id: nil)), keptIn: vault)
        await pro.activate(key)
        #expect(!pro.isUnlocked)
        #expect(vault.stored == nil)
        #expect(pro.note == ProText.licenseUnreachable)
    }

    @Test("Pressing Activate again while the first is out asks once")
    func oneQuestionAtATime() async {
        let gate = GatedAuthority()
        let pro = ProStore(licensedBy: gate, keptIn: MemoryVault())
        let first = Task { await pro.activate(key) }
        while gate.calls == 0 { await Task.yield() }
        #expect(pro.busy)
        await pro.activate(key)   // the second press
        await pro.checkAgain()
        await pro.deactivate()
        #expect(gate.calls == 1)
        gate.open()
        await first.value
        #expect(pro.isUnlocked)
        #expect(gate.calls == 1)
    }

    @Test("A license on this Mac is never replaced by another key: nothing is sent")
    func noSecondKey() async {
        let clock = TestClock()
        let lapsed = License(key: key, instanceID: "ins_9", status: .expired,
                             expires: clock.now.addingTimeInterval(-60), checked: .distantPast)
        let authority = StubAuthority(reply(.active))
        let vault = MemoryVault(lapsed)
        let pro = ProStore(licensedBy: authority, keptIn: vault, now: { clock.now })
        await pro.activate("NR-PRO-ANOTHER-KEY-1234")
        #expect(authority.calls.isEmpty)
        #expect(vault.stored == lapsed)
        #expect(pro.note == ProText.alreadyActivated)
    }

    @Test("A license that doesn't unlock says why; one that does, or none, says nothing here")
    func lockedLine() {
        let clock = TestClock()
        let ended = clock.now.addingTimeInterval(-60)
        let lapsed = License(key: key, instanceID: "ins_9", status: .active, expires: ended, checked: .distantPast)
        let disabled = License(key: key, instanceID: "ins_9", status: .disabled, expires: nil, checked: .distantPast)
        let active = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let authority = StubAuthority(reply(.active))
        #expect(ProStore(licensedBy: authority, keptIn: MemoryVault(lapsed), now: { clock.now }).lockedLicenseLine
                == ProText.licenseNote(.expired, expires: ended), "active but past its year reads as run out")
        #expect(ProStore(licensedBy: authority, keptIn: MemoryVault(disabled)).lockedLicenseLine
                == ProText.licenseNote(.disabled))
        #expect(ProStore(licensedBy: authority, keptIn: MemoryVault(active)).lockedLicenseLine == nil)
        #expect(ProStore(licensedBy: authority, keptIn: MemoryVault()).lockedLicenseLine == nil)
    }

    @Test("A Keychain that couldn't be read at launch is read again before any activation")
    func keychainUnread() async {
        let stored = License(key: key, instanceID: "ins_9", status: .expired, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(load: true)
        let authority = StubAuthority(reply(.active))
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        #expect(pro.license == nil)
        await pro.activate("NR-PRO-ANOTHER-KEY-1234")
        #expect(pro.note == ProText.keychainUnread, "still unreadable: nothing is sent")
        #expect(authority.calls.isEmpty)
        vault.refuse()
        await pro.activate("NR-PRO-ANOTHER-KEY-1234")
        #expect(authority.calls.isEmpty, "readable now, and it holds a license: never written over")
        #expect(pro.license == stored)
        #expect(pro.note == ProText.alreadyActivated)
        #expect(vault.stored == stored)
    }

    @Test("A retry after no answer goes by the same name, so the store lists one Mac")
    func retrySameName() async {
        let authority = StubAuthority(failing: LicenseUnreachable())
        let pro = ProStore(licensedBy: authority, keptIn: MemoryVault())
        await pro.activate(key)
        authority.answer(with: reply(.active))
        await pro.activate(key)
        #expect(pro.isUnlocked)
        let names = authority.calls.compactMap { call -> String? in
            if case .activate(_, let name) = call { return name }
            return nil
        }
        #expect(names.count == 2)
        #expect(Set(names).count == 1)
    }

    @Test("An activation the Keychain won't keep is given back at once")
    func activationNotKept() async {
        let vault = MemoryVault()
        vault.refuse(save: true)
        let authority = StubAuthority(reply(.active, id: "ins_77"))
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        await pro.activate(key)
        #expect(!pro.isUnlocked)
        #expect(pro.license == nil)
        #expect(pro.note == ProText.keychainGivenBack)
        #expect(authority.calls.last == .deactivate(key: key, id: "ins_77"))
    }

    @Test("Not kept and not given back either: its id is held, locked, so Deactivate can give it back")
    func activationHeld() async {
        let vault = MemoryVault()
        vault.refuse(save: true)
        let authority = StubAuthority(reply(.active, id: "ins_77"))
        authority.failDeactivations()
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        await pro.activate(key)
        #expect(!pro.isUnlocked, "an activation that wasn't kept never unlocks")
        #expect(pro.license?.instanceID == "ins_77")
        #expect(pro.license?.status == .inactive)
        #expect(pro.note == ProText.keychainNotGivenBack)
    }

    @Test("A build with a broken relay address keeps Pro locked, and the Keychain as it was")
    func misconfigured() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let pro = ProStore(licensedBy: NoLicenseRelay(), keptIn: vault, misconfigured: true)
        #expect(!pro.isUnlocked)
        #expect(pro.lockedLicenseLine == ProText.licenseUnreachable)
        await pro.checkAgain()
        pro.settle()
        #expect(!pro.isUnlocked)
        #expect(vault.stored == stored)
    }

    @Test("A license kept but not yet understood asks for Check Again")
    func needsCheck() {
        let stored = License(key: key, instanceID: "ins_9", status: .unknown, expires: nil, checked: .distantPast)
        let pro = ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: MemoryVault(stored))
        #expect(!pro.isUnlocked)
        #expect(pro.lockedLicenseLine == ProText.licenseNeedsCheck)
    }

    @Test("No answer: Pro stays as it was, and the note says to try again")
    func unreachable() async {
        let vault = MemoryVault()
        let pro = ProStore(licensedBy: StubAuthority(failing: LicenseUnreachable()), keptIn: vault)
        await pro.activate(key)
        #expect(!pro.isUnlocked)
        #expect(vault.stored == nil)
        #expect(pro.note == ProText.licenseUnreachable)
    }

    @Test("A yearly key that has already run out is kept, but doesn't unlock")
    func expiredAtActivation() async {
        let clock = TestClock()
        let ended = clock.now.addingTimeInterval(-86_400)
        let vault = MemoryVault()
        let pro = ProStore(licensedBy: StubAuthority(reply(.expired, expires: ended)), keptIn: vault, now: { clock.now })
        await pro.activate(key)
        #expect(!pro.isUnlocked)
        #expect(vault.stored?.status == .expired, "kept, so Check Again can find the renewal")
        #expect(pro.note == ProText.licenseNote(.expired, expires: ended))
    }

    @Test("A year that runs out locks Pro without asking anyone")
    func yearRunsOut() async {
        let clock = TestClock()
        let authority = StubAuthority(reply(.active, expires: clock.now.addingTimeInterval(10 * 86_400)))
        let pro = ProStore(licensedBy: authority, keptIn: MemoryVault(), now: { clock.now })
        await pro.activate(key)
        #expect(pro.isUnlocked)
        var told = 0
        pro.onChange = { told += 1 }
        clock.advance(days: 11)
        pro.settle()
        #expect(!pro.isUnlocked)
        #expect(told == 1)
        #expect(authority.calls.count == 1, "only the activation; the lapse needed no call")
    }

    @Test("Check Again finds a renewal")
    func renewal() async {
        let clock = TestClock()
        let lapsed = License(key: key, instanceID: "ins_9", status: .active,
                             expires: clock.now.addingTimeInterval(-60), checked: .distantPast)
        let renewed = clock.now.addingTimeInterval(365 * 86_400)
        let authority = StubAuthority(reply(.active, expires: renewed))
        let vault = MemoryVault(lapsed)
        let pro = ProStore(licensedBy: authority, keptIn: vault, now: { clock.now })
        #expect(!pro.isUnlocked)
        await pro.checkAgain()
        #expect(pro.isUnlocked)
        #expect(pro.note == nil)
        #expect(vault.stored?.expires == renewed)
        #expect(authority.calls == [.validate(key: key, id: "ins_9")])
    }

    @Test("Check Again after a refund locks Pro")
    func refunded() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let pro = ProStore(licensedBy: StubAuthority(reply(.disabled)), keptIn: vault)
        #expect(pro.isUnlocked)
        await pro.checkAgain()
        #expect(!pro.isUnlocked)
        #expect(vault.stored?.status == .disabled)
        #expect(pro.note == ProText.licenseNote(.disabled))
    }

    @Test("Check Again refused means this Mac's activation no longer counts, not too many Macs")
    func checkRefused() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let pro = ProStore(licensedBy: StubAuthority(reply(.rejected, id: nil)), keptIn: vault)
        await pro.checkAgain()
        #expect(!pro.isUnlocked)
        #expect(vault.stored?.status == .inactive)
        #expect(pro.lockedLicenseLine == ProText.licenseNote(.inactive))
    }

    @Test("A refund the Keychain won't save can't unlock Pro again at the next launch")
    func refundNotSaved() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(save: true)
        let pro = ProStore(licensedBy: StubAuthority(reply(.disabled)), keptIn: vault)
        await pro.checkAgain()
        #expect(!pro.isUnlocked)
        #expect(pro.note == ProText.keychainUnsaved)
        #expect(vault.stored == nil, "the old active answer is taken out")
        #expect(!ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: vault).isUnlocked)
    }

    @Test("A refund the Keychain won't save or remove stays a refund at the next launch")
    func refundRemembered() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(save: true, remove: true)
        let revocations = MemoryRevocations()
        let pro = ProStore(licensedBy: StubAuthority(reply(.disabled)), keptIn: vault, revocations: revocations)
        await pro.checkAgain()
        #expect(!pro.isUnlocked)
        #expect(vault.stored == stored, "the Keychain still holds the old record")
        let relaunched = ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: vault, revocations: revocations)
        #expect(!relaunched.isUnlocked)
        #expect(relaunched.license?.status == .inactive)
    }

    @Test("A deactivation the Keychain won't save or remove stays given back at the next launch")
    func deactivationRemembered() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(save: true, remove: true)
        let revocations = MemoryRevocations()
        let pro = ProStore(licensedBy: StubAuthority(reply(.inactive)), keptIn: vault, revocations: revocations)
        await pro.deactivate()
        #expect(!pro.isUnlocked)
        let relaunched = ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: vault, revocations: revocations)
        #expect(!relaunched.isUnlocked)
    }

    @Test("A license kept as active again is no longer remembered as ended")
    func revocationCleared() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let revocations = MemoryRevocations()
        revocations.add("ins_9")
        let pro = ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: vault, revocations: revocations)
        #expect(!pro.isUnlocked)
        await pro.checkAgain()
        #expect(pro.isUnlocked)
        #expect(!revocations.contains("ins_9"))
        #expect(ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: vault, revocations: revocations).isUnlocked)
    }

    @Test("A yearly license locks the moment it runs out, with the app still open")
    func expiresWhileOpen() async {
        let clock = TestClock()
        let sleeper = TestSleeper()
        let authority = StubAuthority(reply(.active, expires: clock.now.addingTimeInterval(10 * 86_400)))
        let pro = ProStore(licensedBy: authority, keptIn: MemoryVault(), now: { clock.now }, sleep: { try await sleeper.sleep($0) })
        await pro.activate(key)
        #expect(pro.isUnlocked)
        for _ in 0..<1_000 where sleeper.asked.isEmpty { await Task.yield() }
        #expect(sleeper.asked.last == .seconds(10 * 86_400))
        var told = 0
        pro.onChange = { told += 1 }
        clock.advance(days: 10)
        sleeper.wake()
        for _ in 0..<1_000 where pro.isUnlocked { await Task.yield() }
        #expect(!pro.isUnlocked)
        #expect(told == 1, "so stamping stops too")
        #expect(authority.calls.count == 1, "only the activation: locking needed no call")
    }

    @Test("A license that never runs out isn't watched")
    func lifetimeUnwatched() async {
        let sleeper = TestSleeper()
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let pro = ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: MemoryVault(stored), sleep: { try await sleeper.sleep($0) })
        for _ in 0..<50 { await Task.yield() }
        #expect(pro.isUnlocked)
        #expect(sleeper.asked.isEmpty)
    }

    @Test("Check Again with no answer, or an answer that isn't one, changes nothing",
          arguments: [true, false])
    func checkAgainUnreachable(_ noAnswer: Bool) async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let authority = noAnswer ? StubAuthority(failing: LicenseUnreachable()) : StubAuthority(reply(.unknown))
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        await pro.checkAgain()
        #expect(pro.isUnlocked)
        #expect(vault.stored == stored)
        #expect(pro.note == ProText.licenseUnreachable)
    }

    @Test("Deactivating gives the activation back and forgets the license here")
    func deactivates() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let authority = StubAuthority(reply(.inactive))
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        await pro.deactivate()
        #expect(!pro.isUnlocked)
        #expect(pro.license == nil)
        #expect(vault.stored == nil)
        #expect(authority.calls == [.deactivate(key: key, id: "ins_9")])
        #expect(pro.note == ProText.deactivated)
    }

    @Test("Deactivating with an answer that isn't one keeps the license and its id")
    func deactivateUnknown() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let pro = ProStore(licensedBy: StubAuthority(reply(.unknown)), keptIn: vault)
        await pro.deactivate()
        #expect(pro.isUnlocked)
        #expect(pro.license == stored)
        #expect(vault.stored == stored)
        #expect(pro.note == ProText.licenseUnreachable)
    }

    @Test("Given back but stuck in the Keychain, the license is kept as given back: locked")
    func deactivateNotRemoved() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(remove: true)
        let pro = ProStore(licensedBy: StubAuthority(reply(.inactive)), keptIn: vault)
        await pro.deactivate()
        #expect(!pro.isUnlocked)
        #expect(pro.license?.status == .inactive)
        #expect(vault.stored?.status == .inactive, "the next launch stays locked")
        #expect(pro.note == ProText.keychainNotCleared)
        vault.refuse()
        await pro.deactivate()   // trying again clears it, without asking the store again
        #expect(pro.license == nil)
        #expect(vault.stored == nil)
    }

    @Test("Trying Deactivate again after the Keychain stuck asks only the Keychain")
    func deactivateRetryLocal() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(remove: true)
        let authority = StubAuthority(reply(.inactive))
        let pro = ProStore(licensedBy: authority, keptIn: vault)
        await pro.deactivate()
        #expect(authority.calls.count == 1)
        authority.fail(with: LicenseUnreachable())   // the store wouldn't answer clearly again
        vault.refuse()
        await pro.deactivate()
        #expect(authority.calls.count == 1, "the store isn't asked a second time")
        #expect(pro.license == nil)
        #expect(pro.note == ProText.deactivated)
    }

    @Test("A Keychain unreadable at launch is read again at the next Pro gate")
    func rereadAtSettle() {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        vault.refuse(load: true)
        let pro = ProStore(licensedBy: StubAuthority(reply(.active)), keptIn: vault)
        #expect(!pro.isUnlocked)
        vault.refuse()
        pro.settle()
        #expect(pro.isUnlocked)
        #expect(pro.license == stored)
    }

    @Test("A year that ran out and won't save keeps its record: the renewal is checked with its id")
    func expiredNotSavedKept() async {
        let clock = TestClock()
        let lapsed = License(key: key, instanceID: "ins_9", status: .expired,
                             expires: clock.now.addingTimeInterval(-60), checked: .distantPast)
        let vault = MemoryVault(lapsed)
        vault.refuse(save: true)
        let pro = ProStore(licensedBy: StubAuthority(reply(.expired, expires: lapsed.expires)), keptIn: vault,
                           now: { clock.now })
        await pro.checkAgain()
        #expect(vault.stored == lapsed)
        #expect(pro.note == ProText.keychainUnsaved)
    }

    @Test("Deactivating offline changes nothing: going offline never costs an activation")
    func deactivateOffline() async {
        let stored = License(key: key, instanceID: "ins_9", status: .active, expires: nil, checked: .distantPast)
        let vault = MemoryVault(stored)
        let pro = ProStore(licensedBy: StubAuthority(failing: LicenseUnreachable()), keptIn: vault)
        await pro.deactivate()
        #expect(pro.isUnlocked)
        #expect(vault.stored == stored)
    }
}

// MARK: - The relay

@Suite("License relay", .serialized) struct LicenseRelayTests {

    @Test("Only an https address with a host and no sign-in is a relay",
          arguments: ["http://netrelish.com/api/license", "https://", "https://user:pw@netrelish.com/api/license",
                      "ftp://netrelish.com/x", "", "netrelish.com/api/license"])
    func refusesAddress(_ address: String) {
        #expect(LicenseRelay(address: address) == nil)
    }

    @Test("netrelish.com's relay is accepted")
    func acceptsAddress() throws {
        let relay = try #require(LicenseRelay(address: "https://netrelish.com/api/license"))
        #expect(relay.url.absoluteString == "https://netrelish.com/api/license")
    }

    @Test("Activating sends the key and this Mac's random name, and nothing else")
    func activateRequest() async throws {
        let host = "activate.relay.test"
        StandInRelay.answer(host, with: .text(#"{"status":"active","instance_id":"ins_42","expires_at":"2027-11-12T08:30:00.000Z"}"#))
        let relay = try StandInRelay.relay(host)
        let answer = try await relay.activate(key: key, instanceName: "NetRelish-0a1b2c3d")
        #expect(answer.status == .active)
        #expect(answer.instanceID == "ins_42")
        #expect(answer.expires == ISO8601DateFormatter().date(from: "2027-11-12T08:30:00Z"))
        let request = try #require(StandInRelay.lastRequest(host))
        #expect(request.method == "POST")
        #expect(request.contentType == "application/json")
        #expect(request.path == "/api/license")
        #expect(request.fields == ["action": "activate", "key": key, "instance_name": "NetRelish-0a1b2c3d"])
    }

    @Test("Checking again and deactivating send the key and the activation id")
    func otherRequests() async throws {
        let host = "validate.relay.test"
        StandInRelay.answer(host, with: .text(#"{"status":"active","instance_id":"ins_42","expires_at":null}"#))
        let relay = try StandInRelay.relay(host)
        let answer = try await relay.validate(key: key, instanceID: "ins_42")
        #expect(answer.expires == nil)
        #expect(StandInRelay.lastRequest(host)?.fields == ["action": "validate", "key": key, "instance_id": "ins_42"])
        _ = try await relay.deactivate(key: key, instanceID: "ins_42")
        #expect(StandInRelay.lastRequest(host)?.fields == ["action": "deactivate", "key": key, "instance_id": "ins_42"])
    }

    @Test("A key the store doesn't know, and one it refuses, are answers, not failures")
    func refusals() async throws {
        let host = "refuse.relay.test"
        let relay = try StandInRelay.relay(host)
        StandInRelay.answer(host, with: .text(#"{"status":"invalid"}"#, status: 404))
        #expect(try await relay.activate(key: key, instanceName: "n").status == .invalid)
        StandInRelay.answer(host, with: .text(#"{"status":"rejected"}"#, status: 409))
        #expect(try await relay.activate(key: key, instanceName: "n").status == .rejected)
    }

    @Test("An activation id that isn't one is dropped, so the answer can't unlock")
    func badInstanceID() async throws {
        let host = "badid.relay.test"
        StandInRelay.answer(host, with: .text(#"{"status":"active","instance_id":"ins 1; drop"}"#))
        let answer = try await StandInRelay.relay(host).activate(key: key, instanceName: "n")
        #expect(answer.instanceID == nil)
        #expect(LicenseRelay.isInstanceID("ins_ABC-123"))
        #expect(!LicenseRelay.isInstanceID(""))
        #expect(!LicenseRelay.isInstanceID(String(repeating: "a", count: 129)))
    }

    @Test("A status the app doesn't know is unknown, never active")
    func unknownStatus() async throws {
        let host = "unknown.relay.test"
        StandInRelay.answer(host, with: .text(#"{"status":"paused","instance_id":"ins_1"}"#))
        let answer = try await StandInRelay.relay(host).activate(key: key, instanceName: "n")
        #expect(answer.status == .unknown)
    }

    @Test("Anything else is no answer at all",
          arguments: [StandInRelay.Answer.text(#"{"error":"not_configured"}"#, status: 503),
                      .text(#"{"error":"upstream"}"#, status: 502),
                      .reply(status: 500, body: Data()),
                      .text("not json"),
                      .text(#"{"instance_id":"ins_1"}"#),
                      // A 404 or 409 that isn't the relay's own verdict: a moved page, a host mid-move.
                      .text("<html><body>Not Found</body></html>", status: 404),
                      .reply(status: 409, body: Data()),
                      .text(#"{"status":"invalid"}"#, status: 409),
                      .text(#"{"status":"rejected"}"#, status: 404),
                      // A date that can't be read is never "doesn't run out".
                      .text(#"{"status":"active","instance_id":"ins_1","expires_at":"2027-13-45"}"#),
                      .text(#"{"status":"active","instance_id":"ins_1","expires_at":12}"#),
                      .failure(URLError(.notConnectedToInternet))])
    func noAnswer(_ answer: StandInRelay.Answer) async throws {
        let host = "fail-\(UUID().uuidString.prefix(8).lowercased()).relay.test"
        StandInRelay.answer(host, with: answer)
        await #expect(throws: LicenseUnreachable.self) {
            _ = try await StandInRelay.relay(host).activate(key: key, instanceName: "n")
        }
    }

    @Test("A redirect is not followed: the key goes to the relay that was asked, and nowhere else")
    func noRedirect() async throws {
        let host = "redirect.relay.test", elsewhere = "elsewhere.relay.test"
        StandInRelay.answer(host, with: .redirect(to: URL(string: "https://\(elsewhere)/steal")!))
        StandInRelay.answer(elsewhere, with: .text(#"{"status":"active","instance_id":"ins_1"}"#))
        await #expect(throws: LicenseUnreachable.self) {
            _ = try await StandInRelay.relay(host).activate(key: key, instanceName: "n")
        }
        #expect(StandInRelay.lastRequest(elsewhere) == nil)
    }

    @Test("A reply longer than an answer is given up on")
    func tooLong() async throws {
        let host = "long.relay.test"
        let padding = String(repeating: " ", count: LicenseRelay.replyLimit)
        StandInRelay.answer(host, with: .text(#"{"status":"active","instance_id":"ins_1"}"# + padding))
        await #expect(throws: LicenseUnreachable.self) {
            _ = try await StandInRelay.relay(host).activate(key: key, instanceName: "n")
        }
    }

    @Test("No address keeps the build without keys; an address that isn't a relay locks Pro")
    func setup() {
        guard case .notSet = LicenseRelay.setup(from: nil) else { Issue.record("nil"); return }
        guard case .notSet = LicenseRelay.setup(from: "  ") else { Issue.record("blank"); return }
        guard case .relay(let relay) = LicenseRelay.setup(from: "https://netrelish.com/api/license") else {
            Issue.record("relay"); return
        }
        #expect(relay.url.host == "netrelish.com")
        guard case .broken = LicenseRelay.setup(from: "http://netrelish.com/api/license") else { Issue.record("http"); return }
        guard case .broken = LicenseRelay.setup(from: "$(NR_LICENSE_ACTIVATION_URL)") else { Issue.record("unexpanded"); return }
    }

    @Test("Dates come with or without fractional seconds")
    func dates() {
        #expect(LicenseRelay.date(from: "2027-01-02T03:04:05Z") != nil)
        #expect(LicenseRelay.date(from: "2027-01-02T03:04:05.678Z") != nil)
        #expect(LicenseRelay.date(from: "next year") == nil)
    }
}

// MARK: - The Keychain

@Suite("License keychain", .serialized) struct LicenseKeychainTests {
    @Test("A record this build can't fully read keeps its key and id, locked, instead of reading as none")
    func salvage() throws {
        let newer = Data(#"{"key":"\#(key)","instanceID":"ins_9","status":"paused","checked":"2027-01-01T00:00:00Z","seats":3}"#.utf8)
        let salvaged = try #require(LicenseKeychain.license(from: newer))
        #expect(salvaged.key == key)
        #expect(salvaged.instanceID == "ins_9")
        #expect(salvaged.status == .unknown)
        #expect(!salvaged.unlocks(at: Date()))
        #expect(LicenseKeychain.license(from: Data("not json".utf8)) == nil)
        #expect(LicenseKeychain.license(from: Data(#"{"key":"\#(key)"}"#.utf8)) == nil, "no id: nothing to keep")
        #expect(LicenseKeychain.license(from: Data(#"{"key":"x y","instanceID":"ins_9"}"#.utf8)) == nil)
    }

    @Test("A license is kept, read back, replaced and removed")
    func roundTrip() throws {
        let vault = LicenseKeychain(service: "com.shepdesign.netrelish.license.tests.\(UUID().uuidString)")
        defer { try? vault.remove() }
        #expect(try vault.load() == nil)
        let first = License(key: key, instanceID: "ins_1", status: .active,
                            expires: Date(timeIntervalSince1970: 1_900_000_000), checked: Date(timeIntervalSince1970: 1_800_000_000))
        try vault.save(first)
        #expect(try vault.load() == first)
        var second = first
        second.status = .disabled
        try vault.save(second)
        #expect(try vault.load() == second)
        try vault.remove()
        #expect(try vault.load() == nil)
    }
}

// MARK: - A stand-in for the relay

/// Answers for the relay, one answer per host so tests side by side don't see each other's,
/// and remembers the last request each host got.
final class StandInRelay: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        case reply(status: Int = 200, body: Data)
        case redirect(to: URL)
        case failure(URLError)

        static func text(_ body: String, status: Int = 200) -> Answer { .reply(status: status, body: Data(body.utf8)) }
    }

    struct Seen: Equatable, Sendable {
        let method: String?
        let path: String
        let contentType: String?
        let fields: [String: String]?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var seen: [String: Seen] = [:]

    static func answer(_ host: String, with answer: Answer) { lock.withLock { answers[host] = answer } }
    static func lastRequest(_ host: String) -> Seen? { lock.withLock { seen[host] } }

    static func relay(_ host: String) throws -> LicenseRelay {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInRelay.self]
        return try #require(LicenseRelay(address: "https://\(host)/api/license", session: URLSession(configuration: configuration)))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        let answer = Self.lock.withLock { () -> Answer? in
            Self.seen[host] = Seen(method: request.httpMethod, path: url.path,
                                   contentType: request.value(forHTTPHeaderField: "Content-Type"), fields: fields)
            return Self.answers[host]
        }
        switch answer {
        case .reply(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
