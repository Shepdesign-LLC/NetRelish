// ComponentGallery.swift — DEBUG-only. Manifest §8, every state, as demos.
// These are mocks for the kit; the real Shelf/Tabs/Bench/Inspector are P1.

#if DEBUG
import SwiftUI

struct ComponentGallery: View {
    var sealTrigger: Int

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp8) {
            HStack(alignment: .top, spacing: NRSpace.sp8) {
                KitCell("Shelf — active row relish100 tint, smart jars under a hairline, New Jar last") { ShelfDemo() }
                KitCell("Tabs — active · inactive · pinned · sinking. Only the active tab carries the lip") { TabsDemo() }
            }
            HStack(alignment: .top, spacing: NRSpace.sp8) {
                KitCell("Primary — default · hover (move the mouse) · disabled. One per view") {
                    HStack(spacing: NRSpace.sp3) {
                        Button("Seal") {}.buttonStyle(.nrPrimary)
                        Button("Seal") {}.buttonStyle(.nrPrimary).disabled(true)
                    }
                }
                KitCell("Secondary — default · disabled") {
                    HStack(spacing: NRSpace.sp3) {
                        Button("New Jar") {}.buttonStyle(.nrSecondary)
                        Button("New Jar") {}.buttonStyle(.nrSecondary).disabled(true)
                    }
                }
                KitCell("Badge") {
                    HStack(spacing: NRSpace.sp3) { NRBadge("412 preserved"); NRBadge("3") }
                }
                KitCell("Focus ring — NRColor.focus (= relish500)") {
                    Text("Search the Pantry")
                        .font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg3)
                        .padding(.horizontal, NRSpace.sp3).padding(.vertical, NRSpace.sp2)
                        .frame(width: 200, alignment: .leading)
                        .background(NRColor.surface, in: RoundedRectangle(cornerRadius: NRRadius.r1))
                        .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.focus, lineWidth: 2))
                }
                KitCell("Shelf-life bars — 80% · 45% · 15% (warn under 20%)") {
                    VStack(spacing: NRSpace.sp3) {
                        NRShelfLifeBar(remaining: 0.8)
                        NRShelfLifeBar(remaining: 0.45)
                        NRShelfLifeBar(remaining: 0.15)
                    }
                    .frame(width: 160)
                }
            }
            HStack(alignment: .top, spacing: NRSpace.sp8) {
                KitCell("Seal — ⌘S. Glyph pulses once, the drip falls (seal · easeJar), tab closes, badge increments") {
                    SealDemo(trigger: sealTrigger)
                }
                KitCell("Bench chrome — surface, hairline-separated. Nothing brand-coloured touches the page") { BenchDemo() }
                KitCell("Inspector — inspectorW, surface2, fsSm labels in fg2") { InspectorDemo() }
            }
            HStack(alignment: .top, spacing: NRSpace.sp8) {
                KitCell("Ask the Pantry — plain rows with jar provenance chips. No chat bubbles") { AskDemo() }
                KitCell("Empty state — cog at 48pt, one line, one primary button") { EmptyStateDemo() }
            }
        }
    }
}

// MARK: - Shelf

struct ShelfDemo: View {
    var body: some View {
        VStack(spacing: 0) {
            shelfRow("Meridian", active: true)
            shelfRow("Research", active: false)
            shelfRow("Taxes", active: false)
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline).padding(.vertical, NRSpace.sp1)
            shelfRow("Recent", active: false, symbol: .jarSmart)
            Button { } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).foregroundStyle(NRColor.fg2).help("New Jar")
        }
        .frame(width: NRSpace.shelfW)
        .padding(.vertical, NRSpace.sp2)
        .background(NRColor.surface2)
        .overlay(alignment: .trailing) { Rectangle().fill(NRColor.hairline).frame(width: NRSpace.hairline) }
        .frame(height: 300, alignment: .top)
        .background(NRColor.surface2)
    }

    private func shelfRow(_ name: String, active: Bool, symbol: NRSymbol = .jar) -> some View {
        VStack(spacing: 2) {
            symbol.image.resizable().frame(width: 20, height: 20)
            Text(name).font(NRType.font(NRType.fsXs)).lineLimit(1)
        }
        .foregroundStyle(active ? NRColor.fg : NRColor.fg2)
        .frame(width: 48, height: 44)
        .background(active ? NRColor.relish100 : .clear, in: RoundedRectangle(cornerRadius: NRRadius.r1))
        .padding(.vertical, 2)
    }
}

// MARK: - Tabs

struct TabsDemo: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            tab("Apple Developer Documentation", state: .active)
            tab("GRDB.swift — GitHub", state: .inactive)
            tab("", state: .pinned)
            tab("Old article from last week", state: .sinking)
        }
        .padding(.horizontal, NRSpace.sp2)
        .padding(.top, NRSpace.sp2)
        .background(NRColor.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline) }
    }

    enum TabState { case active, inactive, pinned, sinking }

    private func tab(_ title: String, state: TabState) -> some View {
        HStack(spacing: NRSpace.sp2) {
            if state == .pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(NRColor.fg2)
            } else {
                Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(NRColor.fg3)
                Text(title).font(NRType.font(NRType.fsSm, weight: state == .active ? .medium : .regular)).lineLimit(1)
            }
        }
        .foregroundStyle(state == .sinking ? NRColor.fg3 : NRColor.fg)
        .padding(.horizontal, NRSpace.sp3)
        .frame(width: state == .pinned ? 34 : 170, height: NRSpace.tabH)
        .background(state == .active ? NRColor.surface : .clear,
                    in: UnevenRoundedRectangle(topLeadingRadius: NRRadius.r2, topTrailingRadius: NRRadius.r2))
        .overlay(alignment: .top) {
            if state == .active { NRTabLip().padding(.horizontal, NRSpace.sp2) }
        }
    }
}

// MARK: - Bench / Inspector

struct BenchDemo: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NRSpace.sp2) {
                Image(systemName: "chevron.left").foregroundStyle(NRColor.fg3)
                Image(systemName: "chevron.right").foregroundStyle(NRColor.fg3)
                Text("developer.apple.com/documentation/swiftui")
                    .font(NRType.font(NRType.fsSm, design: NRType.fontMono)).foregroundStyle(NRColor.fg2)
                    .padding(.horizontal, NRSpace.sp2).frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NRColor.surface2, in: RoundedRectangle(cornerRadius: NRRadius.r1))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(NRSpace.sp2)
            .background(NRColor.surface)
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            Text("the page").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)   // the page is the page; never tinted
        }
        .frame(width: 300, height: 140)
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        .clipShape(RoundedRectangle(cornerRadius: NRRadius.r2))
    }
}

struct InspectorDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Item", rows: [("Kind", "page"), ("Jar", "Meridian"), ("Captured", "Today 9:14")])
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            section("Labels", rows: [("client", ""), ("spec", "")])
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            section("Shelf life", rows: [("Sinks in", "2 days")])
        }
        .frame(width: NRSpace.inspectorW, alignment: .leading)
        .background(NRColor.surface2)
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        .clipShape(RoundedRectangle(cornerRadius: NRRadius.r2))
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            Text(title.uppercased()).font(NRType.font(NRType.fsXs, weight: .medium)).foregroundStyle(NRColor.fg2)
            ForEach(rows, id: \.0) { k, v in
                HStack {
                    Text(k).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                    Spacer()
                    Text(v).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg)
                }
            }
        }
        .padding(NRSpace.sp3)
    }
}

// MARK: - Ask the Pantry / Empty state

struct AskDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NRSpace.sp2) {
                Image(systemName: "magnifyingglass").foregroundStyle(NRColor.fg3)
                Text("what did the client say about the invoice").font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg)
            }
            .padding(NRSpace.sp3)
            .background(NRColor.surface)
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            row("Invoice terms — Meridian Rebuild kickoff notes", jar: "Meridian")
            row("Re: revised invoice schedule", jar: "Meridian")
            row("Net-30 vs net-45 — quick comparison", jar: "Taxes")
        }
        .frame(width: 420)
        .background(NRColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        .clipShape(RoundedRectangle(cornerRadius: NRRadius.r2))
    }

    private func row(_ title: String, jar: String) -> some View {
        HStack(spacing: NRSpace.sp3) {
            Text(title).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg).lineLimit(1)
            Spacer()
            HStack(spacing: NRSpace.sp1) {
                NRSymbol.jar.image.resizable().frame(width: 12, height: 12)
                Text(jar).font(NRType.font(NRType.fsXs))
            }
            .foregroundStyle(NRColor.fg2)
            .padding(.horizontal, NRSpace.sp2).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        }
        .padding(.horizontal, NRSpace.sp3).padding(.vertical, NRSpace.sp2)
    }
}

struct EmptyStateDemo: View {
    var body: some View {
        VStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image.resizable().frame(width: 48, height: 48)
            Text("Nothing in this jar yet.").font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2)
            Button("Capture a page") {}.buttonStyle(.nrPrimary)
        }
        .frame(width: 300, height: 180)
        .background(NRColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NRRadius.r2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        .clipShape(RoundedRectangle(cornerRadius: NRRadius.r2))
    }
}
#endif
