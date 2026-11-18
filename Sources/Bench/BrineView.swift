// BrineView.swift — the smart jars on the Bench: Brine, Today, Sealed, Sinking soon (manifest
// v2.1 §8, ADR 0035). The canvas, a header with the smart jar's tile, then plain rows in float
// cards, grouped Today / Yesterday / Earlier (Sinking soon is one card). Each row carries its
// jar's provenance: the jar drawn small and its name. Each is a query, so a row's button acts
// on the item or tab where it already is; nothing here moves anything into a smart jar
// (non-negotiable 2).

import Pantry
import SwiftUI

struct SmartJarView: View {
    let smart: SmartJar
    @Bindable var workbench: Workbench

    var body: some View {
        if workbench.count(of: smart) == 0 {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 34)
                    .padding(.horizontal, 44)
                EmptyBench(message: smart.emptyMessage)
            }
            .background(NRColor.canvas)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    rows
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
            (smart == .brine ? NRSymbol.sink : NRSymbol.jarSmart).image.resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(NRColor.fg2)
                .frame(width: 44, height: 44)
                .background(NRColor.tab, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(smart.name)
                    .font(NRType.font(NRType.fs2xl, weight: .semibold)).tracking(-0.4)
                    .foregroundStyle(NRColor.fg).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text("\(badge) · \(smart.blurb)")
                    .font(NRType.font(NRType.fsSm, weight: .medium)).monospacedDigit()
                    .foregroundStyle(NRColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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
            grouped(workbench.brine, by: \.updatedAt) { item, isLast in
                SmartJarRowView(title: item.title, host: item.domain, icon: Pantry.Tab(url: item.url),
                                jar: jar(item.sunkOriginJarId), fill: fill(item.sunkOriginJarId),
                                when: when("Sank", item.updatedAt), action: "Restore", isLast: isLast) { workbench.restore(item) }
                    // Drag a row onto a jar on the Shelf, or pick the jar here: it reopens there.
                    .draggable(DragPayload.brine(item.id).string)
                    .contextMenu {
                        ForEach(workbench.jars) { target in
                            Button("Restore to \(target.name)") { workbench.restore(item, into: target.id) }
                        }
                    }
            }
        case .today:
            grouped(workbench.today, by: { $0.sealedAt ?? $0.createdAt }) { item, isLast in
                SmartJarRowView(title: item.title, host: item.domain, icon: Pantry.Tab(url: item.url),
                                jar: jar(item.jarId ?? item.sunkOriginJarId), fill: fill(item.jarId ?? item.sunkOriginJarId),
                                when: when(item.state == .sealed ? "Sealed" : "Added", item.sealedAt ?? item.createdAt),
                                action: "Open", isLast: isLast) { workbench.open(item) }
            }
        case .sealed:
            grouped(workbench.sealedItems, by: { $0.sealedAt ?? $0.createdAt }) { item, isLast in
                SmartJarRowView(title: item.title, host: item.domain, icon: Pantry.Tab(url: item.url),
                                jar: jar(item.jarId), fill: fill(item.jarId),
                                when: when("Sealed", item.sealedAt ?? item.createdAt), action: "Open", isLast: isLast) { workbench.open(item) }
            }
        case .sinking:
            let tabs = workbench.sinkingSoon
            SmartJarCard {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    SmartJarRowView(title: tabTitle(tab), host: tab.url.flatMap { URL(string: $0)?.host },
                                    icon: tab, glyph: workbench.glyph(of: tab),
                                    jar: jar(tab.jarId), fill: fill(tab.jarId),
                                    when: sinkingWhen(tab), action: "Open", isLast: index == tabs.count - 1) { workbench.open(tab) }
                }
            }
            .padding(.top, 32)
        }
    }

    /// Items under Today, Yesterday and Earlier, each group one card. Groups keep the items'
    /// own order, and an empty group shows nothing.
    private func grouped<Row: View>(_ items: [Item], by date: (Item) -> Date,
                                    @ViewBuilder row: @escaping (Item, Bool) -> Row) -> some View {
        let groups = SmartJarDay.groups(items, date: date, now: workbench.now)
        return ForEach(groups, id: \.day) { group in
            SmartJarSectionHeader(title: group.day.title, count: group.items.count)
            SmartJarCard {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    row(item, index == group.items.count - 1)
                }
            }
        }
    }

    private func jar(_ id: String?) -> Jar? { id.flatMap { id in workbench.jars.first { $0.id == id } } }

    private func fill(_ id: String?) -> Double { jar(id).map { workbench.fill(of: $0) } ?? 0 }

    /// "Sank 2 hours ago", "Sealed yesterday".
    private func when(_ verb: String, _ date: Date) -> String {
        "\(verb) \(date.formatted(.relative(presentation: .named)))"
    }

    private func tabTitle(_ tab: Tab) -> String {
        if let title = tab.title, !title.isEmpty { return title }
        return tab.url ?? "New Tab"
    }

    private func sinkingWhen(_ tab: Tab) -> String {
        guard let jar = jar(tab.jarId), let left = ShelfLife.timeLeft(of: tab, in: jar, now: workbench.now) else {
            return ""
        }
        return "Sinks \(workbench.now.addingTimeInterval(left).formatted(.relative(presentation: .named)))"
    }
}

/// The day a smart jar's row falls under, from the date it sank, came in or was sealed.
enum SmartJarDay: Int, CaseIterable {
    case today, yesterday, earlier

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .earlier: "Earlier"
        }
    }

    static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> SmartJarDay {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        // A date ahead of now (a clock that moved) still reads as today, never as earlier.
        return date > now ? .today : .earlier
    }

    struct Group {
        let day: SmartJarDay
        let items: [Item]
    }

    /// The items by day, Today first; empty days are left out.
    static func groups(_ items: [Item], date: (Item) -> Date, now: Date,
                       calendar: Calendar = .current) -> [Group] {
        var byDay: [SmartJarDay: [Item]] = [:]
        for item in items { byDay[of(date(item), now: now, calendar: calendar), default: []].append(item) }
        return allCases.compactMap { day in byDay[day].map { Group(day: day, items: $0) } }
    }
}

/// "TODAY 1": a group's label in small caps, then its count.
private struct SmartJarSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NRSpace.sp2) {
            Text(title.uppercased())
            Text("\(count)").monospacedDigit()
        }
        .font(NRType.font(NRType.fsXs, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(NRColor.fg3)
        .padding(.top, 32)
        .padding(.bottom, NRSpace.sp3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A float card that holds a group's rows: r10, a 1pt hairline.
private struct SmartJarCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) { content }
            .background(NRColor.float)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
    }
}

/// One row in a smart jar, 56pt: the page's icon, its title and site, the jar it belongs to,
/// and when. Under the pointer, "when" gives way to the row's one button.
struct SmartJarRowView: View {
    let title: String
    let host: String?
    /// The tab whose icon the row shows: the open tab itself, or one made from an item's address.
    let icon: Tab
    var glyph: String? = nil
    let jar: Jar?
    let fill: Double
    let when: String
    let action: String
    var isLast: Bool = false
    let perform: () -> Void
    @State private var hovering = false
    /// The row's button has the keyboard (Full Keyboard Access): it shows, as under the pointer.
    @FocusState private var buttonFocused: Bool

    /// The button shows under the pointer and while it has the keyboard.
    private var showsButton: Bool { hovering || buttonFocused }

    var body: some View {
        HStack(spacing: NRSpace.sp3) {
            TabIcon(tab: icon, glyph: glyph, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? (icon.url ?? "Untitled") : title)
                    .font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                if let host, !host.isEmpty {
                    Text(host).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let jar {
                    NRFilledJar(paint: jar.paint, fill: fill, size: 18, isActive: false)
                    Text(jar.name).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2).lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
            ZStack(alignment: .trailing) {
                Text(when)
                    .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3).lineLimit(1)
                    .padding(.trailing, NRSpace.sp1)
                    .opacity(showsButton ? 0 : 1)
                SmartJarRowButton(title: action, perform: perform)
                    .focused($buttonFocused)
                    .opacity(showsButton ? 1 : 0)
                    .allowsHitTesting(showsButton)
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(hovering ? NRColor.tab.opacity(0.5) : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(NRColor.hairlineSoft).frame(height: NRSpace.hairline) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: showsButton)
        // A view at opacity 0 leaves the accessibility tree, so the faded button can't be
        // relied on there: the row is one element that reads as a whole and carries the
        // button's action, named, and as its default.
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(action)) { perform() }
        .accessibilityAction { perform() }
    }
}

/// The row's small secondary button: "Restore" or "Open".
private struct SmartJarRowButton: View {
    let title: String
    let perform: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            Label(title, systemImage: title == "Restore" ? "arrow.uturn.backward" : "arrow.up.right")
                .font(NRType.font(NRType.fsSm, weight: .medium))
                .foregroundStyle(NRColor.fg2)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(hovering ? NRColor.tab : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
