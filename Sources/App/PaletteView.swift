// PaletteView.swift — ⌘K. A 52pt field row and a list in a 12pt-radius box, floating over the Bench column on a
// flat scrim (manifest v2.1 §8, ADR 0035): the float fill, a hairline and the soft float
// shadow. Rows come in three groups, Pantry, Open tabs and Commands; the selected row is the
// tab grey. The only relish is the caret (the focus color, placement #7). ↑↓ moves, ⏎ runs,
// Esc or a click on the scrim closes. No icons beyond §7 and SF Symbols; no emoji.

import Pantry
import SwiftUI

struct PaletteView: View {
    @Bindable var workbench: Workbench
    @State private var query = ""
    @State private var selection = 0
    @State private var pantry: [PaletteRow] = []
    @FocusState private var focused: Bool

    static let width: CGFloat = 560

    /// Pantry → Open tabs → Commands: the order the list shows and ↑↓ moves through.
    private var rows: [PaletteRow] {
        pantry + PaletteSource.tabRows(for: query, workbench: workbench) + PaletteSource.rows(for: query, workbench: workbench)
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            field
            if !rows.isEmpty {
                list(rows)
            }
        }
        .frame(width: Self.width)
        .nrFloat(cornerRadius: 12)
        .onAppear { focused = true }
        .task {
            // An overlay can arrive before its window gives it the keyboard: ask once more.
            await Task.yield()
            focused = true
        }
        .onChange(of: query) { _, new in
            selection = 0
            pantry = PaletteSource.pantryRows(for: new, workbench: workbench)
        }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Palette")
    }

    private var field: some View {
        HStack(spacing: NRSpace.sp3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NRColor.fg3)
                .accessibilityHidden(true)
            TextField("Search the Pantry, or type a command", text: $query)
                .textFieldStyle(.plain)
                .font(NRType.font(16))
                .foregroundStyle(NRColor.fg)
                .tint(NRColor.focus)                 // the caret: relish placement #7
                .focused($focused)
                .onSubmit(run)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
            PaletteKeyCap("esc")
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NRColor.hairlineSoft).frame(height: NRSpace.hairline)
        }
    }

    private func list(_ rows: [PaletteRow]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 0) {
                            if index == 0 || rows[index - 1].group != row.group {
                                PaletteGroupHeader(group: row.group)
                            }
                            PaletteRowView(row: row, selected: index == selection)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = index; run() }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selection) { _, new in
                guard rows.indices.contains(new) else { return }
                proxy.scrollTo(rows[new].id)
            }
        }
    }

    private func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func run() {
        let rows = self.rows
        guard rows.indices.contains(selection) else { return }
        let row = rows[selection]
        close()
        row.run()
    }

    private func close() {
        workbench.showPalette = false
    }
}

/// "Pantry", "Open tabs", "Commands": small caps in fg3, as the board's section heads.
private struct PaletteGroupHeader: View {
    let group: PaletteRow.Group

    private var title: String {
        switch group {
        case .pantry: "Pantry"
        case .tabs: "Open tabs"
        case .commands: "Commands"
        }
    }

    var body: some View {
        Text(title.uppercased())
            .font(NRType.font(NRType.fsXs, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(NRColor.fg3)
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A shortcut or "esc", in a hairline key cap.
private struct PaletteKeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(NRType.font(NRType.fsXs, weight: .medium))
            .foregroundStyle(NRColor.fg3)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
    }
}

private struct PaletteRowView: View {
    let row: PaletteRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(row.title)
                .font(NRType.font(NRType.fsMd, weight: .medium))
                .foregroundStyle(NRColor.fg)
                .lineLimit(1)
                .layoutPriority(1)
            if row.kind == .command, let subtitle = row.subtitle {
                Text(subtitle)
                    .font(NRType.font(NRType.fsSm))
                    .foregroundStyle(NRColor.fg3)
                    .lineLimit(1)
            }
            Spacer(minLength: NRSpace.sp3)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(selected ? NRColor.tab : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private var isSmartJar: Bool {
        row.kind == .jar && SmartJar.allCases.contains { "jar.\($0.rawValue)" == row.id }
    }

    @ViewBuilder
    private var icon: some View {
        switch row.kind {
        case .item:
            if let url = row.url {
                TabIcon(tab: Pantry.Tab(url: url), size: 16)
            } else {
                Image(systemName: row.systemImage ?? "doc.text")
                    .font(.system(size: 13)).foregroundStyle(NRColor.fg2)
            }
        case .tab:
            TabIcon(tab: Pantry.Tab(url: row.url), glyph: row.glyph, size: 16)
        case .jar:
            if isSmartJar {
                NRSymbol.jarSmart.image.resizable().frame(width: 16, height: 16)
                    .foregroundStyle(NRColor.fg2)
            } else {
                NRFilledJar(paint: JarPaint(css: row.jarTint), fill: 0.5, size: 14, isActive: false)
            }
        case .command:
            if row.id == "cmd.seal" {
                NRSymbol.seal.image.resizable().frame(width: 16, height: 16)
                    .foregroundStyle(NRColor.fg2)
            } else if let name = row.systemImage {
                Image(systemName: name)
                    .font(.system(size: 13)).foregroundStyle(NRColor.fg2)
            }
        }
    }

    /// Where a row comes from ("Sealed · <jar>", the jar, or Brine), or its shortcut.
    @ViewBuilder
    private var trailing: some View {
        switch row.kind {
        case .item, .tab:
            HStack(spacing: 6) {
                if row.sealed {
                    Text("Sealed ·")
                }
                if let jarId = row.jarId, !jarId.isEmpty {
                    NRFilledJar(paint: JarPaint(css: row.jarTint), fill: 0.5, size: 14, isActive: false)
                } else {
                    NRSymbol.sink.image.resizable().frame(width: 13, height: 13)
                }
                if let subtitle = row.subtitle {
                    Text(subtitle).lineLimit(1)
                }
            }
            .font(NRType.font(NRType.fsSm))
            .foregroundStyle(NRColor.fg3)
        case .command, .jar:
            if let shortcut = row.shortcut {
                PaletteKeyCap(shortcut)
            }
        }
    }
}
