// ProView.swift — the NetRelish Pro sheet (ADR 0023): what Pro adds, the two prices, buying,
// and restoring. Opened from the app menu, or by using a Pro feature while it's locked.
//
// Brand: the cog mark (allowed in onboarding-like moments, manifest §2), one primary button
// (Lifetime, "Buy once, use forever."), everything else neutral. No new tokens.

import StoreKit
import SwiftUI

struct ProView: View {
    @Bindable var pro: ProStore
    /// Closes the sheet. Passed in so snapshots can render the view with no Workbench.
    let done: () -> Void
    @Environment(\.purchase) private var purchase

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp5) {
            header
            features
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            if pro.isUnlocked {
                unlocked
            } else {
                offers
            }
            if let note = pro.note {
                Text(note).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(NRSpace.sp6)
        .frame(width: 440)
        .background(NRColor.surface)
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image
                .resizable().scaledToFit().frame(width: NRSpace.sp10, height: NRSpace.sp10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProText.title)
                    .font(NRType.font(NRType.fsXl, weight: .semibold)).foregroundStyle(NRColor.fg)
                Text(ProText.lead)
                    .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            }
            Spacer()
            Button("Done") { done() }
                .buttonStyle(.nrSecondary)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp3) {
            ForEach(Array(zip(ProText.featureNames, ProText.featureLines)), id: \.0) { name, line in
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg)
                    Text(line).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var unlocked: some View {
        Text(ProText.unlocked(plan: pro.plan, renews: pro.renews))
            .font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var offers: some View {
        if pro.offers.isEmpty {
            Text(ProText.storeUnreachable)
                .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: NRSpace.sp3) {
                ForEach(pro.offers) { offer in
                    HStack(spacing: NRSpace.sp3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(offer.plan.name)
                                .font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg)
                            Text(ProText.planLine(offer.plan))
                                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
                        }
                        Spacer()
                        // One primary button per view (manifest §4): Lifetime carries it.
                        if offer.plan == .lifetime {
                            Button(ProText.buy(offer)) { buy(offer.plan) }.buttonStyle(.nrPrimary)
                        } else {
                            Button(ProText.buy(offer)) { buy(offer.plan) }.buttonStyle(.nrSecondary)
                        }
                    }
                }
            }
            .disabled(pro.busy)
        }
    }

    private var footer: some View {
        HStack(spacing: NRSpace.sp3) {
            if !pro.isUnlocked {
                Button(ProText.restore) { Task { await pro.restore() } }
                    .buttonStyle(.plain).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
                    .disabled(pro.busy)
            } else if pro.plan == .annual {
                Link(ProText.manage, destination: ProText.manageURL)
                    .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
            }
            Spacer()
            Link(ProText.terms, destination: ProText.termsURL)
                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
            Link(ProText.privacy, destination: ProText.privacyURL)
                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
        }
    }

    private func buy(_ plan: ProPlan) {
        Task { await pro.buy(plan, with: purchase) }
    }
}

/// The neutral tag beside a Pro feature's button while Pro is locked. Not a count, so it
/// isn't the relish badge (manifest §4 row 6); hairline and fg2, like any other label.
struct ProTag: View {
    var body: some View {
        Text(ProText.badge.uppercased())
            .font(NRType.font(NRType.fsXs, weight: .medium))
            .foregroundStyle(NRColor.fg2)
            .padding(.horizontal, NRSpace.sp1)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: NRRadius.r1)
                .strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
            .accessibilityLabel("Part of NetRelish Pro")
    }
}
