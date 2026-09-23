// MeOnboardingSheet.swift — shown the first time ⌘⇧F is pressed with an empty card.
// Manifest §7: the cog at 48pt is the onboarding placement. One line, two buttons.

import SwiftUI

struct MeOnboardingSheet: View {
    var vault: VaultStore = .live
    /// Called after a successful import so the fill that was asked for can happen.
    var imported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image.resizable().frame(width: 48, height: 48)
            Text("Fill forms from your card").font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)
            Text("Your card stays in your Keychain. NetRelish fills forms only when you ask.")
                .font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2).multilineTextAlignment(.center)
            if let message {
                Text(message).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).multilineTextAlignment(.center)
            }
            HStack(spacing: NRSpace.sp3) {
                Button("Fill it in by hand") { dismiss(); openSettings() }.buttonStyle(.nrSecondary)
                Button(importing ? "Importing…" : "Import from my card") { importFromContacts() }
                    .buttonStyle(.nrPrimary).keyboardShortcut(.defaultAction).disabled(importing)
            }
        }
        .padding(NRSpace.sp6)
        .frame(width: 420)
        .background(NRColor.surface)
    }

    private func importFromContacts() {
        importing = true
        Task { @MainActor in
            defer { importing = false }
            do {
                let me = try await ContactsImport.meCard()
                guard !me.isEmpty else { message = "Your Contacts card is empty. Fill it in by hand instead."; return }
                try vault.save(me, for: nil)
                dismiss()
                imported()
            } catch { message = "\(error)" }
        }
    }
}
