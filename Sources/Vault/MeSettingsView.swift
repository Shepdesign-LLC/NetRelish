// MeSettingsView.swift — Settings → Me. The card, an Import button, and Clear. Every edit
// writes straight to the Keychain; there is no Save button because there is nothing to
// stage. Errors show inline in fg2 — no alert theater.

import SwiftUI

struct MeSettingsView: View {
    var vault: VaultStore = .live
    @State private var identity = Identity()
    @State private var loaded = false
    @State private var message: String?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp4) {
            Text("Your card stays in your Keychain. NetRelish fills forms with it only when you press ⌘⇧F.")
                .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            IdentityFields(identity: $identity)
            HStack(spacing: NRSpace.sp3) {
                Button(importing ? "Importing…" : "Import from my card") { importFromContacts() }
                    .buttonStyle(.nrSecondary).disabled(importing)
                Button("Clear") { identity = Identity() }.buttonStyle(.nrSecondary).disabled(identity.isEmpty)
                Spacer()
            }
            if let message {
                Text(message).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NRSpace.sp6)
        .frame(width: 560)
        .background(NRColor.surface)
        .onAppear(perform: load)
        .onChange(of: identity) { _, new in persist(new) }
    }

    private func load() {
        do { identity = try vault.identity(for: nil) ?? Identity() } catch { message = "\(error)" }
        loaded = true
    }

    private func persist(_ new: Identity) {
        guard loaded else { return }
        do {
            if new.isEmpty { try vault.remove(for: nil) } else { try vault.save(new, for: nil) }
            message = nil
        } catch { message = "\(error)" }
    }

    private func importFromContacts() {
        importing = true
        Task { @MainActor in
            defer { importing = false }
            do {
                identity = try await ContactsImport.meCard()
                message = identity.isEmpty ? "Your Contacts card is empty." : "Imported. Contacts won't be read again."
            } catch { message = "\(error)" }
        }
    }
}
