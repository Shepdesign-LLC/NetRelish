// ComparisonView.swift — Reseal & diff on the Bench: two seals of one page, side by side, in
// one scroll so the two columns always line up.
//
// Monochrome by decision (Ryan, Nov 5; ADR 0021): what the older seal lost is struck through
// in fg3, what the newer one gained is underlined in fg, and changed rows sit on surface2.
// No new colors, no relish (manifest §4).

import Pantry
import SwiftUI

struct ComparisonView: View {
    let comparison: Workbench.Comparison
    @Bindable var workbench: Workbench

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            columnTitles
            hairline
            content
        }
        .background(NRColor.surface)
        .onExitCommand { workbench.closeComparison() }
    }

    private var hairline: some View {
        Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(comparison.newer.title)
                    .font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                Text(ComparisonText.subtitle(comparison))
                    .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
            }
            Spacer()
            Button("Done") { workbench.closeComparison() }
                .buttonStyle(.nrSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: NRSpace.sp12)
        .background(NRColor.surface)
    }

    private var columnTitles: some View {
        HStack(spacing: 0) {
            columnTitle(ComparisonText.columnTitle(comparison.older))
            Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline)
            columnTitle(ComparisonText.columnTitle(comparison.newer))
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(NRColor.surface2)
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(NRType.font(NRType.fsXs, weight: .medium)).foregroundStyle(NRColor.fg2)
            .padding(.horizontal, NRSpace.sp4).padding(.vertical, NRSpace.sp2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        if !comparison.hasText {
            note(ComparisonText.noText)
        } else if let diff = comparison.diff {
            if diff.isUnchanged {
                note(ComparisonText.unchanged)
            } else {
                // One scroll for both columns: linked scroll by construction.
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(diff.rows) { row in
                            ComparisonRow(row: row)
                        }
                    }
                    .padding(.vertical, NRSpace.sp2)
                }
            }
        } else {
            note(ComparisonText.working)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NRColor.surface)
    }
}

private struct ComparisonRow: View {
    let row: PageDiff.Row

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(row.old)
            Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline)
            cell(row.new)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(row.isChange ? NRColor.surface2 : NRColor.surface)
    }

    @ViewBuilder private func cell(_ spans: [PageDiff.Span]?) -> some View {
        Group {
            if let spans {
                Text(ComparisonText.styled(spans))
                    .font(NRType.font(NRType.fsMd))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(ComparisonText.spoken(spans))
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .padding(.horizontal, NRSpace.sp4).padding(.vertical, NRSpace.sp1)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The comparison's words and styling, kept out of the views so tests can read them.
enum ComparisonText {
    static let working = "Comparing the two seals…"
    static let unchanged = "Nothing changed between these two seals."
    static let noText = "These seals kept no article text to compare."

    static func columnTitle(_ item: Item) -> String {
        item.sealedAt.map { "Sealed " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Sealed"
    }

    static func subtitle(_ comparison: Workbench.Comparison) -> String {
        guard let diff = comparison.diff else { return "Comparing" }
        let n = diff.changeCount
        let changes = n == 0 ? "No changes" : n == 1 ? "1 change" : "\(n) changes"
        return [changes, comparison.newer.domain].compactMap { $0 }.joined(separator: " · ")
    }

    /// Removed words struck through in fg3, added words underlined in fg, the rest in fg.
    static func styled(_ spans: [PageDiff.Span]) -> AttributedString {
        var out = AttributedString()
        for (index, span) in spans.enumerated() {
            if index > 0 { out += AttributedString(" ") }
            var piece = AttributedString(span.text)
            switch span.kind {
            case .same:
                piece.foregroundColor = NRColor.fg
            case .removed:
                piece.foregroundColor = NRColor.fg3
                piece.strikethroughStyle = .single
            case .added:
                piece.foregroundColor = NRColor.fg
                piece.underlineStyle = .single
            }
            out += piece
        }
        return out
    }

    /// What VoiceOver reads, since strikethrough and underline aren't spoken.
    static func spoken(_ spans: [PageDiff.Span]) -> String {
        spans.map { span in
            switch span.kind {
            case .same: span.text
            case .removed: "Removed: \(span.text)"
            case .added: "Added: \(span.text)"
            }
        }
        .joined(separator: " ")
    }
}
