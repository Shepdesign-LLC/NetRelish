// JarBoard.swift — a jar's board on the Bench (manifest v2.1 §8, ADR 0035): on the canvas,
// the jar drawn large (it shows the jar's level; there is no fill bar) with its name and what's
// in it, its open tabs as tiles, and what the jar keeps as cards. Clicking a jar on the Shelf,
// the jar's chip in the address row, or the mark opens it. Everything here is a query over
// what the jar already holds; the board moves nothing. Hand-written.

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

    /// "tabs sink after 7 idle days", after the summary on the board's header. The shelf life
    /// in the Panel's words (PanelText.days), with "idle" before its unit.
    static func sinkLine(days: Double) -> String {
        let span = PanelText.days(days)
        let parts = span.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return "tabs sink after \(span) idle" }
        return "tabs sink after \(parts[0]) idle \(parts[1])"
    }

    private var meta: String {
        let summary = Self.summary(tabs: tabs.count, kept: kept.count)
        guard let days = jar.shelfLifeDays, days > 0 else { return summary }
        return "\(summary) · \(Self.sinkLine(days: days))"
    }

    var body: some View {
        if tabs.isEmpty && kept.isEmpty {
            // Nothing to show but the way in: the header keeps its two buttons (Edit Jar… and
            // New Tab), and the cog says the jar is empty.
            VStack(spacing: 0) {
                header
                    .padding(.top, 34)
                    .padding(.horizontal, 44)
                EmptyBench(message: "Nothing in here yet.")
            }
            .background(NRColor.canvas)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    header
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
                .padding(EdgeInsets(top: 34, leading: 44, bottom: 40, trailing: 44))
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(NRColor.canvas)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            NRFilledJar(paint: paint, fill: workbench.fill(of: jar), size: 46, isActive: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(jar.name)
                    .font(NRType.font(NRType.fs2xl, weight: .semibold)).tracking(-0.4)
                    .foregroundStyle(NRColor.fg).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(meta)
                    .font(NRType.font(NRType.fsSm, weight: .medium)).monospacedDigit()
                    .foregroundStyle(NRColor.fg3).lineLimit(1)
            }
            .padding(.top, 2)
            Spacer(minLength: NRSpace.sp4)
            HStack(spacing: NRSpace.sp2) {
                Button("Edit Jar…") { workbench.requestEditActiveJar() }.buttonStyle(.nrSecondary)
                Button { workbench.newTab(in: jar.id) } label: {
                    Label("New Tab", systemImage: "plus")
                }
                .buttonStyle(JarButtonStyle(paint: paint))
            }
            .padding(.top, 6)
        }
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NRSpace.sp3) {
            HStack(alignment: .firstTextBaseline, spacing: NRSpace.sp2) {
                Text(title.uppercased())
                Text("\(count)").monospacedDigit()
            }
            .font(NRType.font(NRType.fsXs, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(NRColor.fg3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: NRSpace.sp3) { content() }
        }
        .padding(.top, 32)
    }
}

/// The board's one filled button, in the jar's own color (manifest v2.1 jar-color list): 28pt,
/// r8, the jar's 500 step, its 300 step under the pointer. Relish only for a Relish jar.
struct JarButtonStyle: ButtonStyle {
    let paint: JarPaint

    func makeBody(configuration: Configuration) -> some View {
        JarButtonBody(configuration: configuration, paint: paint)
    }

    private struct JarButtonBody: View {
        let configuration: Configuration
        let paint: JarPaint
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(NRType.font(NRType.fsMd, weight: .semibold))
                // The ink follows the step shown: a face that takes white can hover to a light
                // edge300 that needs black.
                .foregroundStyle(hovering && isEnabled ? paint.edgeInk : paint.ink)
                .padding(.horizontal, NRSpace.sp3)
                .frame(height: 28)
                .background(hovering && isEnabled ? paint.edge300 : paint.face, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.4))
                .onHover { hovering = $0 }
                .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        }
    }
}

/// A card on the board: a float box with a hairline that takes the jar's color under the
/// pointer.
private struct BoardCard<Content: View>: View {
    let paint: JarPaint
    var minHeight: CGFloat = 64
    let open: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    init(paint: JarPaint, minHeight: CGFloat = 64, open: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.paint = paint
        self.minHeight = minHeight
        self.open = open
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(NRColor.float, in: RoundedRectangle(cornerRadius: NRRadius.r2))
            .overlay(RoundedRectangle(cornerRadius: NRRadius.r2)
                .strokeBorder(hovering ? paint.face : NRColor.hairline, lineWidth: NRSpace.hairline))
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .onHover { hovering = $0 }
            // A tap gesture, not a Button, so a tile can still be dragged onto a jar. The
            // keyboard gets the same: focus with Tab, open with Space or Return.
            .focusable()
            .onKeyPress(.space) { open(); return .handled }
            .onKeyPress(.return) { open(); return .handled }
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
            HStack(spacing: 11) {
                TabIcon(tab: tab, glyph: glyph, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NRType.font(NRType.fsMd, weight: .semibold)).foregroundStyle(NRColor.fg).lineLimit(1)
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
            .padding(.horizontal, 14)
            .frame(height: 64)
        }
    }
}

/// One thing the jar keeps: what it is and when, the Sealed pill if it's sealed, its title, a
/// few lines of it, and where it came from. Opening a sealed one shows its saved copy.
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

    /// "PAGE · NOV 12": the kind, and the day it was sealed or came in.
    static func provenance(_ item: Item) -> String {
        let when = (item.state == .sealed ? item.sealedAt : nil) ?? item.createdAt
        return "\(item.kind.rawValue) · \(when.formatted(.dateTime.month(.abbreviated).day()))".uppercased()
    }

    var body: some View {
        BoardCard(paint: paint, minHeight: 168, open: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text(Self.provenance(item))
                        .font(NRType.font(NRType.fsXs, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(NRColor.fg3).lineLimit(1)
                    Spacer(minLength: 0)
                    if item.state == .sealed {
                        NRSealedPill(size: .small)
                    }
                }
                .frame(height: 22)
                Text(item.title.isEmpty ? (item.url ?? "Untitled") : item.title)
                    .font(NRType.font(NRType.fsMd + 1, weight: .semibold))
                    .foregroundStyle(NRColor.fg)
                    .lineLimit(2)
                    .padding(.top, 10)
                if let excerpt = item.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(NRType.font(NRType.fsSm))
                        .foregroundStyle(NRColor.fg2)
                        .lineLimit(3)
                        .padding(.top, 6)
                }
            }
            // Room at the bottom for the footer, which sits on the card's bottom edge.
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14 + 16 + NRSpace.sp3, trailing: 16))
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .overlay(alignment: .bottomLeading) {
                footer
                    .frame(height: 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .help(Self.detail(item))
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if let domain = item.domain, !domain.isEmpty {
                TabIcon(tab: Pantry.Tab(url: item.url), size: 14)
                Text(domain).lineLimit(1)
            } else {
                Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(NRColor.fg2)
                    .accessibilityHidden(true)
                Text(item.kind.rawValue.capitalized).lineLimit(1)
            }
        }
        .font(NRType.font(NRType.fsSm))
        .foregroundStyle(NRColor.fg3)
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
