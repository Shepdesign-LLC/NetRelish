// Pro.swift — the one place a Pro feature asks whether Pro is unlocked (ADR 0003, ADR 0012).
//
// Buying and restoring Pro (StoreKit 2, and the direct build's license key) isn't built yet,
// so for now everything is unlocked and Pro features can be demoed. When purchases land, this
// is the only line that changes (ADR 0021).

enum Pro {
    static var isUnlocked: Bool { true }

    /// What a locked Pro feature says, once there is a lock.
    static let lockedLine = "Reseal & diff is part of NetRelish Pro."

    /// What Export Proof says when Pro is locked.
    static let proofLockedLine = "Export Proof is part of NetRelish Pro."
}
