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
    /// The rotor's entries find their rows by id in here.
    @Namespace private var rowSpace
    /// The Workbench is every window's: only the key window speaks for it.
    @Environment(\.controlActiveState) private var activeState

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
        // The diff arrives a moment after the Bench switches to it, silently: say how it came
        // out. A view per comparison (the Bench gives each its own id), so each says it once.
        .onChange(of: comparison.diff?.changeCount, initial: true) { _, _ in
            guard activeState == .key, let line = ComparisonText.announcement(comparison) else { return }
            NRAnnounce.post(line)
        }
    }

    private var hairline: some View {
        Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(comparison.newer.title)
                    .font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(ComparisonText.subtitle(comparison))
                    .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
                    .accessibilityLabel(PanelText.spokenList(ComparisonText.subtitle(comparison)))
            }
            Spacer()
            Button("Done") { workbench.closeComparison() }
                .buttonStyle(.nrSecondary)
                .nrFocusRing()
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
        .background(NRColor.surface)   // surface2 is kept for changed rows
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(NRType.font(NRType.fsXs, weight: .medium)).foregroundStyle(NRColor.fg2)
            .padding(.horizontal, NRSpace.sp4).padding(.vertical, NRSpace.sp2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)          // drawn in capitals; "Nov" is never spelled out
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var content: some View {
        if !comparison.hasText {
            note(ComparisonText.noText)
        } else if let diff = comparison.diff {
            if diff.isUnchanged {
                note(ComparisonText.unchanged)
            } else {
                // One scroll for both columns: linked scroll by construction. VoiceOver's rotor
                // goes straight from change to change, past the rows that stayed the same; the
                // rows are lazy, so an entry scrolls its row in before VoiceOver goes there.
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(diff.rows) { row in
                                ComparisonRow(row: row)
                                    .id(row.id)
                                    .accessibilityRotorEntry(id: row.id, in: rowSpace)
                            }
                        }
                        .padding(.vertical, NRSpace.sp2)
                    }
                    .accessibilityRotor(Text("Changes")) {
                        ForEach(diff.rows.filter(\.isChange)) { row in
                            AccessibilityRotorEntry(Text(verbatim: ComparisonText.rotorLabel(row)), id: row.id, in: rowSpace) {
                                proxy.scrollTo(row.id)
                            }
                        }
                    }
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(row.old)
            Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline)
            cell(row.new)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(row.isChange ? NRColor.surface2 : NRColor.surface)
        // One element per row: an unchanged sentence is read once, not once per column, and
        // a change says what it was.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ComparisonText.spokenRow(row))
    }

    @ViewBuilder private func cell(_ spans: [PageDiff.Span]?) -> some View {
        Group {
            if let spans {
                Text(ComparisonText.styled(spans, contrast: contrast))
                    .font(NRType.font(NRType.fsMd))
                    .lineSpacing(NRType.fsMd * (NRType.lhBody - 1))
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

    /// What VoiceOver says once the comparison is worked out: how many changes, or the
    /// note shown instead. Nil while it's still being worked out.
    static func announcement(_ comparison: Workbench.Comparison) -> String? {
        guard comparison.hasText else { return noText }
        guard let diff = comparison.diff else { return nil }
        let n = diff.changeCount
        return n == 0 ? unchanged : n == 1 ? "1 change" : "\(n) changes"
    }

    /// Removed words struck through in fg3, added words underlined in fg, the rest in fg.
    /// Under Increase Contrast, removed words are fg2: the strike still marks them.
    static func styled(_ spans: [PageDiff.Span], contrast: ColorSchemeContrast = .standard) -> AttributedString {
        var out = AttributedString()
        for (index, span) in spans.enumerated() {
            if index > 0 { out += AttributedString(" ") }
            var piece = AttributedString(span.text)
            switch span.kind {
            case .same:
                piece.foregroundColor = NRColor.fg
            case .removed:
                piece.foregroundColor = contrast == .increased ? NRColor.fg2 : NRColor.fg3
                piece.strikethroughStyle = Text.LineStyle.single
            case .added:
                piece.foregroundColor = NRColor.fg
                piece.underlineStyle = Text.LineStyle.single
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

    /// A row as VoiceOver reads it. Unchanged, the sentence once. A sentence only the older
    /// seal has is "Removed", only the newer "Added"; one in both is read before and after.
    static func spokenRow(_ row: PageDiff.Row) -> String {
        guard row.isChange else { return plain(row.new ?? row.old ?? []) }
        switch (row.old, row.new) {
        case (let old?, nil): return "Removed: \(plain(old))"
        case (nil, let new?): return "Added: \(plain(new))"
        case (let old?, let new?): return "Changed. Before: \(sentence(spoken(old))) After: \(spoken(new))"
        case (nil, nil): return ""
        }
    }

    /// How much of a change the Changes rotor shows.
    static let rotorLength = 60

    /// A change in the Changes rotor: what kind, then the start of what it says now (what it
    /// said, for a removal).
    static func rotorLabel(_ row: PageDiff.Row) -> String {
        let kind: String
        let spans: [PageDiff.Span]
        switch (row.old, row.new) {
        case (nil, let new?): kind = "Added"; spans = new
        case (let old?, nil): kind = "Removed"; spans = old
        default: kind = "Changed"; spans = row.new ?? row.old ?? []
        }
        let text = plain(spans)
        guard text.count > rotorLength else { return "\(kind): \(text)" }
        let cut = String(text.prefix(rotorLength)).trimmingCharacters(in: .whitespaces)
        return "\(kind): \(cut)…"
    }

    /// The words alone, with no marks.
    private static func plain(_ spans: [PageDiff.Span]) -> String {
        spans.map(\.text).joined(separator: " ")
    }

    /// Ends with a full stop, so VoiceOver pauses before what follows.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}
