// PaletteView.swift — ⌘K. One field and a list, over the Bench. Manifest §8: surface, a
// hairline border, r2, the focus ring in relish and nothing else brand-colored. ↑↓ moves,
// ⏎ runs, Esc closes. No icons beyond §7 and SF Symbols; no emoji.

import Pantry
import SwiftUI

struct PaletteView: View {
    @Bindable var workbench: Workbench
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @State private var pantry: [PaletteRow] = []
    @FocusState private var focused: Bool

    private var rows: [PaletteRow] { PaletteSource.rows(for: query, workbench: workbench) + pantry }

    var body: some View {
        VStack(spacing: 0) {
            field
            if !rows.isEmpty {
                Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
                list
            }
        }
        .frame(width: 520)
        .background(NRColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: NRRadius.r2))
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        .onAppear { focused = true }
        .onChange(of: query) { _, new in
            selection = 0
            pantry = PaletteSource.pantryRows(for: new, workbench: workbench)
        }
        .onExitCommand { dismiss() }
    }

    private var field: some View {
        HStack(spacing: NRSpace.sp3) {
            Image(systemName: "magnifyingglass").foregroundStyle(NRColor.fg3)
            TextField("Search the Pantry, or type a command", text: $query)
                .textFieldStyle(.plain)
                .font(NRType.font(NRType.fsLg))
                .foregroundStyle(NRColor.fg)
                .focused($focused)
                .onSubmit(run)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: 52)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        PaletteRowView(row: row, selected: index == selection)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = index; run() }
                    }
                }
            }
            .frame(maxHeight: 320)
            .onChange(of: selection) { _, new in
                guard rows.indices.contains(new) else { return }
                proxy.scrollTo(rows[new].id)
            }
        }
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + delta + rows.count) % rows.count
    }

    private func run() {
        guard rows.indices.contains(selection) else { return }
        let row = rows[selection]
        dismiss()
        row.run()
    }
}

private struct PaletteRowView: View {
    let row: PaletteRow
    let selected: Bool

    var body: some View {
        HStack(spacing: NRSpace.sp3) {
            glyph
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg).lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3).lineLimit(1)
                }
            }
            Spacer(minLength: NRSpace.sp3)
            if let shortcut = row.shortcut {
                Text(shortcut).font(NRType.font(NRType.fsXs, design: NRType.fontMono)).foregroundStyle(NRColor.fg3)
            }
        }
        .padding(.horizontal, NRSpace.sp4)
        .frame(height: 44)
        .background(selected ? NRColor.relish100 : .clear)   // manifest §4: the active row's tint
    }

    @ViewBuilder
    private var glyph: some View {
        if row.kind == .jar {
            NRSymbol.jar.image.resizable().frame(width: 16, height: 16)
                .foregroundStyle(row.tint ?? NRColor.fg2)
        } else if let name = row.systemImage {
            Image(systemName: name).font(.system(size: 12)).foregroundStyle(NRColor.fg3).frame(width: 16)
        }
    }
}
