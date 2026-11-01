// BrineView.swift — the smart jars on the Bench: Brine, Today, Sealed, Sinking soon. Plain
// rows (manifest §8 "Ask the Pantry" rules: rows, jar provenance, no chat bubbles). Each is
// a query, so a row's button acts on the item or tab where it already is; nothing here
// moves anything into a smart jar (non-negotiable 2).

import Pantry
import SwiftUI

struct SmartJarView: View {
    let smart: SmartJar
    @Bindable var workbench: Workbench

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            if workbench.count(of: smart) == 0 {
                EmptyBench(message: smart.emptyMessage)
            } else {
                List { rows }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
            }
        }
        .background(NRColor.surface)
    }

    private var header: some View {
        HStack(spacing: NRSpace.sp3) {
            (smart == .brine ? NRSymbol.sink : NRSymbol.jarSmart).image.resizable()
                .frame(width: 20, height: 20).foregroundStyle(NRColor.fg2)
            Text(smart.name).font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)
            NRBadge(badge)
            Spacer()
            Text(smart.blurb).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3).lineLimit(1)
        }
        .padding(NRSpace.sp4)
    }

    private var badge: String {
        let n = workbench.count(of: smart)
        switch smart {
        case .brine: return "\(n) sunk"
        case .today: return "\(n) new"
        case .sealed: return "\(n) sealed"
        case .sinking: return "\(n) sinking"
        }
    }

    @ViewBuilder private var rows: some View {
        switch smart {
        case .brine:
            ForEach(workbench.brine) { item in
                SmartJarRowView(title: item.title, detail: detail(item, "sank", item.updatedAt),
                                jar: jar(item.sunkOriginJarId), action: "Restore") { workbench.restore(item) }
            }
        case .today:
            ForEach(workbench.today) { item in
                SmartJarRowView(title: item.title,
                                detail: detail(item, item.state == .sealed ? "sealed" : "added", item.sealedAt ?? item.createdAt),
                                jar: jar(item.jarId ?? item.sunkOriginJarId), action: "Open") { workbench.open(item) }
            }
        case .sealed:
            ForEach(workbench.sealedItems) { item in
                SmartJarRowView(title: item.title, detail: detail(item, "sealed", item.sealedAt ?? item.createdAt),
                                jar: jar(item.jarId), action: "Open") { workbench.open(item) }
            }
        case .sinking:
            ForEach(workbench.sinkingSoon) { tab in
                SmartJarRowView(title: tabTitle(tab), detail: sinkingDetail(tab),
                                jar: jar(tab.jarId), action: "Open") { workbench.open(tab) }
            }
        }
    }

    private func jar(_ id: String?) -> Jar? { id.flatMap { id in workbench.jars.first { $0.id == id } } }

    private func detail(_ item: Item, _ verb: String, _ when: Date) -> String {
        [item.domain, "\(verb) \(when.formatted(.relative(presentation: .named)))"].compactMap { $0 }.joined(separator: " · ")
    }

    private func tabTitle(_ tab: Tab) -> String {
        if let title = tab.title, !title.isEmpty { return title }
        return tab.url ?? "New Tab"
    }

    private func sinkingDetail(_ tab: Tab) -> String {
        let domain = tab.url.flatMap { URL(string: $0)?.host }
        guard let jar = jar(tab.jarId), let left = ShelfLife.timeLeft(of: tab, in: jar, now: workbench.now) else {
            return domain ?? ""
        }
        let when = workbench.now.addingTimeInterval(left).formatted(.relative(presentation: .named))
        return [domain, "sinks \(when)"].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One row in a smart jar: a title, a line of detail, the jar it belongs to, one button.
struct SmartJarRowView: View {
    let title: String
    let detail: String
    let jar: Jar?
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: NRSpace.sp3) {
            Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(NRColor.fg3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg).lineLimit(1)
                Text(detail).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2).lineLimit(1)
            }
            Spacer()
            if let jar {
                HStack(spacing: NRSpace.sp1) {
                    NRSymbol.jar.image.resizable().frame(width: 12, height: 12)
                    Text(jar.name).font(NRType.font(NRType.fsXs))
                }
                .foregroundStyle(NRColor.fg2)
                .padding(.horizontal, NRSpace.sp2).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
            }
            Button(action, action: perform).buttonStyle(.nrSecondary)
        }
        .padding(.vertical, NRSpace.sp1)
        .listRowSeparatorTint(NRColor.hairline)
    }
}
