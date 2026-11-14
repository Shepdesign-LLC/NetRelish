// JarBoard.swift — a jar's board on the Bench (manifest v2.0 §8, Workstation v5 spec §6.5):
// the jar drawn large with its name and what's in it, the fill bar, its open tabs as
// tiles, and what the jar keeps as cards. Clicking a jar on the Shelf, the jar's chip in
// the tab strip, or the mark opens it. Everything here is a query over what the jar already
// holds; the board moves nothing. Hand-written.

import Pantry
import SwiftUI

struct JarBoard: View {
    let jar: Jar
    @Bindable var workbench: Workbench

    private let columns = [GridItem(.adaptive(minimum: 252), spacing: NRSpace.sp3, alignment: .top)]
    private var paint: JarPaint { jar.paint }
    private var tabs: [Tab] { workbench.tabs }
    private var kept: [Item] { workbench.jarItems }

    /// "3 tabs · 12 kept", for the board's header and the Panel.
    static func summary(tabs: Int, kept: Int) -> String {
        "\(tabs) \(tabs == 1 ? "tab" : "tabs") · \(kept) kept"
    }

    /// The line beside the fill bar.
    static func fillLine(count: Int, holds: Int) -> String {
        count >= holds ? "\(count) in this jar. It's full" : "\(count) in this jar"
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: NRSpace.sp6) {
                header
                fillBar
                if tabs.isEmpty && kept.isEmpty {
                    Text("Nothing in \(jar.name) yet. Press ⌘T to open a tab here.")
                        .font(NRType.font(NRType.fsLg)).foregroundStyle(NRColor.fg2)
                }
                if !tabs.isEmpty {
                    section("Open tabs", count: tabs.count) {
                        ForEach(tabs) { tab in
                            TabTile(tab: tab, glyph: workbench.glyph(of: tab), paint: paint) { workbench.activateTab(tab) }
                                .contextMenu {
                                    Button(tab.isPinned ? "Unpin" : "Pin") { workbench.togglePin(tab) }
                                    Button("Copy Link") { workbench.copyLink(of: tab) }.disabled(tab.url?.isEmpty != false)
                                    Divider()
                                    Button("Close") { workbench.closeTab(tab) }
                                }
                                .draggable(DragPayload.tab(tab.id).string)
                        }
                    }
                }
                if !kept.isEmpty {
                    section("Kept", count: kept.count) {
                        ForEach(kept) { item in
                            KeptCard(item: item, paint: paint) { workbench.open(item) }
                        }
                    }
                }
            }
            .padding(NRSpace.sp8)
            .frame(maxWidth: 1160, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NRColor.surface)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: NRSpace.sp4) {
            NRFilledJar(paint: paint, fill: workbench.fill(of: jar), size: 46)
            VStack(alignment: .leading, spacing: NRSpace.sp1) {
                Text(jar.name).font(.system(size: 30, weight: .semibold)).tracking(-0.6)
                    .foregroundStyle(NRColor.fg).lineLimit(1)
                Text(Self.summary(tabs: tabs.count, kept: kept.count))
                    .font(NRType.font(NRType.fsLg)).foregroundStyle(NRColor.fg2)
            }
            Spacer(minLength: NRSpace.sp4)
            Button("Edit Jar…") { workbench.requestEditActiveJar() }.buttonStyle(.nrSecondary)
            Button { workbench.newTab(in: jar.id) } label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(JarButtonStyle(paint: paint))
        }
    }

    private var fillBar: some View {
        HStack(spacing: NRSpace.sp3) {
            Capsule().fill(NRColor.hairline)
                .frame(width: 300, height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [paint.face, paint.base], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, 300 * workbench.fill(of: jar)), height: 8)
                        .opacity(workbench.count(in: jar) == 0 ? 0 : 1)
                }
                .accessibilityHidden(true)
            Text(Self.fillLine(count: workbench.count(in: jar), holds: Workbench.jarHolds))
                .font(NRType.font(NRType.fsMd)).monospacedDigit().foregroundStyle(NRColor.fg3)
        }
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NRSpace.sp3) {
            HStack(spacing: NRSpace.sp2) {
                Text(title).font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg2)
                Text("\(count)").font(NRType.font(NRType.fsSm)).monospacedDigit().foregroundStyle(NRColor.fg3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: NRSpace.sp3) { content() }
        }
    }
}

/// The board's one filled button, in the jar's own color.
struct JarButtonStyle: ButtonStyle {
    let paint: JarPaint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NRType.font(NRType.fsMd, weight: .semibold))
            .foregroundStyle(paint.ink)
            .padding(.horizontal, NRSpace.sp4)
            .padding(.vertical, NRSpace.sp2)
            .background(paint.face, in: RoundedRectangle(cornerRadius: NRRadius.r2))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A card on the board: a hairline box that takes the jar's color on its border under the
/// pointer.
private struct BoardCard<Content: View>: View {
    let paint: JarPaint
    let open: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    init(paint: JarPaint, open: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.paint = paint
        self.open = open
        self.content = content()
    }

    var body: some View {
        content
            .padding(NRSpace.sp4)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(NRColor.bg, in: RoundedRectangle(cornerRadius: NRRadius.r3))
            .overlay(RoundedRectangle(cornerRadius: NRRadius.r3)
                .strokeBorder(hovering ? paint.face : NRColor.hairline, lineWidth: NRSpace.hairline))
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
    }
}

/// One open tab on the board: its icon, title and site, and a pin mark if it's pinned.
struct TabTile: View {
    let tab: Tab
    var glyph: String? = nil
    let paint: JarPaint
    let open: () -> Void

    private var title: String { (tab.title?.isEmpty == false ? tab.title : tab.url) ?? "New Tab" }
    private var host: String? { tab.url.flatMap { URL(string: $0)?.host } }

    var body: some View {
        BoardCard(paint: paint, open: open) {
            HStack(spacing: NRSpace.sp3) {
                TabIcon(tab: tab, glyph: glyph, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NRType.font(NRType.fsLg, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                    if let host {
                        Text(host).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if tab.isPinned {
                    Image(systemName: "pin").font(.system(size: 11)).foregroundStyle(NRColor.fg3)
                        .help("Pinned: it never sinks").accessibilityLabel("Pinned")
                }
            }
        }
    }
}

/// One thing the jar keeps: its title, where it came from and when, and the Seal glyph if
/// it's sealed. Opening a sealed one shows its saved copy.
struct KeptCard: View {
    let item: Item
    let paint: JarPaint
    let open: () -> Void

    /// "example.com · sealed 2 days ago".
    static func detail(_ item: Item) -> String {
        let sealed = item.state == .sealed
        let when = (sealed ? item.sealedAt : nil) ?? item.createdAt
        let age = when.formatted(.relative(presentation: .named))
        return [item.domain, "\(sealed ? "sealed" : "added") \(age)"].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        BoardCard(paint: paint, open: open) {
            VStack(alignment: .leading, spacing: NRSpace.sp2) {
                HStack(alignment: .firstTextBaseline, spacing: NRSpace.sp2) {
                    RoundedRectangle(cornerRadius: 4).fill(paint.face).frame(width: 11, height: 11)
                        .accessibilityHidden(true)
                    Text(item.title).font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if item.state == .sealed {
                        NRSymbol.seal.image.resizable().frame(width: 14, height: 14)
                            .foregroundStyle(NRColor.relish500).accessibilityLabel("Sealed")
                    }
                }
                if let excerpt = item.excerpt, !excerpt.isEmpty {
                    Text(excerpt).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2).lineLimit(3)
                }
                Text(Self.detail(item)).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3).lineLimit(1)
            }
        }
    }
}

/// The six jar colors as a row of swatches; the jar's own is ringed.
struct JarSwatches: View {
    /// The jar's stored tint.
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: NRSpace.sp2) {
            ForEach(JarTint.presets) { preset in
                let isOn = (selected ?? JarTint.presets[0].css) == preset.css
                Button { pick(preset.css) } label: {
                    RoundedRectangle(cornerRadius: 9).fill(preset.color)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(NRColor.fg, lineWidth: isOn ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
