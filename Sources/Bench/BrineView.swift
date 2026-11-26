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
    /// The row with the keyboard, by id. The parent holds it so the arrow keys can move it
    /// from row to row, across the day cards, in the order drawn.
    @FocusState private var focusedRow: String?

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
                    // Two sentences to the ear, so the dot between them isn't read out.
                    .accessibilityLabel(Self.spokenSummary(Self.spokenCount(smart, count: workbench.count(of: smart)),
                                                             blurb: smart.blurb))
            }
            Spacer(minLength: 0)
        }
    }

    private var badge: String { Self.badge(smart, count: workbench.count(of: smart)) }

    /// "3 sunk": the count on a smart jar's header, in that jar's own word.
    static func badge(_ smart: SmartJar, count n: Int) -> String {
        switch smart {
        case .brine: "\(n) sunk"
        case .today: "\(n) new"
        case .sealed: "\(n) sealed"
        case .sinking: "\(n) sinking"
        }
    }

    /// The count as the header says it aloud. Brine's drawn "3 sunk" counts captures and pages
    /// shared from another app too, so to the ear it's the Brine pill's words, "3 items".
    static func spokenCount(_ smart: SmartJar, count: Int) -> String {
        smart == .brine ? ShellText.brineValue(count: count, fresh: 0) : Self.badge(smart, count: count)
    }

    /// The header's line as VoiceOver reads it: "3 items. Tabs sink here when…".
    static func spokenSummary(_ count: String, blurb: String) -> String { "\(count). \(blurb)" }

    /// The date a grouped smart jar files a row under: when it sank in Brine, when it was
    /// sealed or came in elsewhere. The rows and the arrow keys both use it, so the keys walk
    /// the rows in the order they're drawn.
    static func groupDate(_ smart: SmartJar) -> (Item) -> Date {
        switch smart {
        case .brine: return { item in item.updatedAt }
        case .today, .sealed, .sinking: return { item in item.sealedAt ?? item.createdAt }
        }
    }

    /// The items' ids as drawn: Today's card, then Yesterday's, then Earlier's.
    static func order(_ items: [Item], by date: (Item) -> Date, now: Date, calendar: Calendar = .current) -> [String] {
        SmartJarDay.groups(items, date: date, now: now, calendar: calendar).flatMap { $0.items.map(\.id) }
    }

    @ViewBuilder private var rows: some View {
        switch smart {
        case .brine:
            grouped(workbench.brine, by: Self.groupDate(.brine)) { item, isLast in
                keys(SmartJarRowView(title: item.title, host: item.domain, icon: Pantry.Tab(url: item.url),
                                     jar: jar(item.sunkOriginJarId), fill: fill(item.sunkOriginJarId),
                                     when: when("Sank", item.updatedAt), action: "Restore",
                                     fromJar: true, hint: Self.restoreHint(jarName: restoreJar(for: item)?.name),
                                     isLast: isLast, isFocused: focusedRow == item.id) { restore(item) }, id: item.id)
                    // Drag a row onto a jar on the Shelf, or pick the jar here: it reopens there.
                    .draggable(DragPayload.brine(item.id).string)
                    .contextMenu {
                        ForEach(workbench.jars) { target in
                            Button("Restore to \(target.name)") { restore(item, into: target) }
                        }
                    }
                    // The menu again, for VoiceOver: this is how a capture gets from Brine into
                    // the jar you pick without dragging. The same names, the same work.
                    .accessibilityActions {
                        ForEach(workbench.jars) { target in
                            Button("Restore to \(target.name)") { restore(item, into: target) }
                        }
                    }
            }
        case .today:
            grouped(workbench.today, by: Self.groupDate(.today)) { item, isLast in
                keys(SmartJarRowView(title: item.title, host: item.domain, icon: Pantry.Tab(url: item.url),
                                     jar: jar(item.jarId ?? item.sunkOriginJarId), fill: fill(item.jarId ?? item.sunkOriginJarId),
                                     when: when(item.state == .sealed ? "Sealed" : "Added", item.sealedAt ?? item.createdAt),
                                     // A sunk item shows the jar it sank from, so it says "from".
                                     action: "Open", fromJar: item.jarId == nil,
                                     isLast: isLast, isFocused: focusedRow == item.id) { workbench.open(item) },
                     id: item.id)
            }
        case .sealed:
            grouped(workbench.sealedItems, by: Self.groupDate(.sealed)) { item, isLast in
                keys(SmartJarRowView(title: item.title, host: item.domain, icon: Pantry.Tab(url: item.url),
                                     jar: jar(item.jarId), fill: fill(item.jarId),
                                     when: when("Sealed", item.sealedAt ?? item.createdAt), action: "Open",
                                     isLast: isLast, isFocused: focusedRow == item.id) { workbench.open(item) },
                     id: item.id)
            }
        case .sinking:
            let tabs = workbench.sinkingSoon
            SmartJarCard {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    keys(SmartJarRowView(title: tabTitle(tab), host: tab.url.flatMap { URL(string: $0)?.host },
                                         icon: tab, glyph: workbench.glyph(of: tab),
                                         jar: jar(tab.jarId), fill: fill(tab.jarId),
                                         when: sinkingWhen(tab), action: "Open", hint: Self.sinkingHint,
                                         isLast: index == tabs.count - 1, isFocused: focusedRow == tab.id) { workbench.open(tab) },
                         id: tab.id)
                }
            }
            .padding(.top, 32)
        }
    }

    // MARK: The keyboard

    /// Every row's id in the order drawn, for the arrow keys.
    private var rowOrder: [String] {
        switch smart {
        case .brine: Self.order(workbench.brine, by: Self.groupDate(.brine), now: workbench.now)
        case .today: Self.order(workbench.today, by: Self.groupDate(.today), now: workbench.now)
        case .sealed: Self.order(workbench.sealedItems, by: Self.groupDate(.sealed), now: workbench.now)
        case .sinking: workbench.sinkingSoon.map(\.id)
        }
    }

    /// A row takes the keyboard by its id, and Up and Down move it to the row above or below.
    private func keys<Row: View>(_ row: Row, id: String) -> some View {
        row.focused($focusedRow, equals: id)
            .onKeyPress(.downArrow) { step(from: id, by: 1) }
            .onKeyPress(.upArrow) { step(from: id, by: -1) }
    }

    /// The id `offset` rows from `id` in `ids`; nil past either end, or when `id` isn't there.
    static func neighbor(of id: String, in ids: [String], by offset: Int) -> String? {
        guard offset != 0, let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }

    /// Moves the keyboard to the next row or the one before. At the first or last row the key
    /// is left alone, as in the tab strip.
    private func step(from id: String, by offset: Int) -> KeyPress.Result {
        guard let next = Self.neighbor(of: id, in: rowOrder, by: offset) else { return .ignored }
        focusedRow = next
        return .handled
    }

    // MARK: Restore

    /// The jar a plain Restore opens in, picked as `Workbench.restore` picks it: the jar the
    /// page sank from, else the first jar.
    private func restoreJar(for item: Item) -> Jar? { jar(item.sunkOriginJarId) ?? workbench.jars.first }

    /// The row's Restore: back into the jar it sank from. The Bench leaves Brine for the page,
    /// so VoiceOver is told where it went. The jar fills once, after the write, as on every
    /// other way into a jar (rearranging.md).
    private func restore(_ item: Item) {
        let target = restoreJar(for: item)
        workbench.restore(item)
        guard let target else { return }
        workbench.fillJar(target.id)
        NRAnnounce.post(Self.restoreAnnouncement(jarName: target.name), priority: .high)
    }

    /// Restore to a jar you picked, from the menu or VoiceOver: the same work as dropping the
    /// row on that jar, the fill included (every way into a jar plays it, once, after the write).
    private func restore(_ item: Item, into target: Jar) {
        workbench.restore(item, into: target.id)
        workbench.fillJar(target.id)
        NRAnnounce.post(Self.restoreAnnouncement(jarName: target.name), priority: .high)
    }

    /// What VoiceOver hears after a restore: the Shelf's words for a Brine row dropped on a
    /// jar, since it's the same move.
    static func restoreAnnouncement(jarName: String) -> String { JarTile.openedLine(jarName: jarName) }

    /// A Brine row's hint: where its Restore goes. Nil when there's no jar to go to.
    static func restoreHint(jarName: String?) -> String? { jarName.map { "Opens it again in \($0)." } }

    /// A Sinking soon row's hint: opening it is what keeps it.
    static let sinkingHint = "Opens it, and its shelf life starts over."

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
        // "Today, 1, heading": the name in its own case (small caps are only drawn, and short
        // capitals can be read letter by letter), then the count.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(String(count))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A float card that holds a group's rows: r10, a 1pt hairline. With Increase Contrast the
/// edge darkens to fg3, so the card still has one.
private struct SmartJarCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) { content }
            .background(NRColor.float)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(contrast == .increased ? NRColor.fg3 : NRColor.hairline, lineWidth: NRSpace.hairline))
    }
}

/// One row in a smart jar, 56pt: the page's icon, its title and site, the jar it belongs to,
/// and when. Under the pointer, or with the keyboard on the row, "when" gives way to the
/// row's one button.
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
    /// In Brine the jar is the one the page sank from; everywhere else it's the one it's in.
    var fromJar: Bool = false
    /// What the row's default action does, where its name doesn't say it all.
    var hint: String? = nil
    var isLast: Bool = false
    /// The row has the keyboard. The smart jar holds the focus, so Up and Down can move it.
    var isFocused: Bool = false
    let perform: () -> Void
    @State private var hovering = false
    /// The button itself has the keyboard. It is taken out of the Tab loop below, so this
    /// should stay false; if it ever does get focus, it shows rather than sit unseen.
    @FocusState private var buttonFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    /// The button shows under the pointer and while the row, or the button, has the keyboard.
    private var showsButton: Bool { hovering || isFocused || buttonFocused }

    /// The secondary text: fg3, or fg2 with Increase Contrast.
    private var quiet: Color { contrast == .increased ? NRColor.fg2 : NRColor.fg3 }

    /// What the row is called: its title, else its address, else "Untitled".
    static func displayTitle(title: String, url: String?) -> String {
        title.isEmpty ? (url ?? "Untitled") : title
    }

    /// What VoiceOver hears after the title, the same whether or not the button is showing:
    /// "juniperbakery.example, from Juniper Bakery, sank 2 hours ago" in Brine, "…, in Juniper
    /// Bakery, sinks in 2 days" elsewhere. Missing parts are left out, commas and all.
    static func spokenValue(host: String?, jarName: String?, fromJar: Bool, when: String) -> String {
        var parts: [String] = []
        if let host, !host.isEmpty { parts.append(host) }
        if let jarName, !jarName.isEmpty { parts.append("\(fromJar ? "from" : "in") \(jarName)") }
        if let first = when.first { parts.append(first.lowercased() + String(when.dropFirst())) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: NRSpace.sp3) {
            TabIcon(tab: icon, glyph: glyph, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.displayTitle(title: title, url: icon.url))
                    .font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                if let host, !host.isEmpty {
                    Text(host).font(NRType.font(NRType.fsSm)).foregroundStyle(quiet).lineLimit(1)
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
                    .font(NRType.font(NRType.fsSm)).foregroundStyle(quiet).lineLimit(1)
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
            if !isLast {
                Rectangle().fill(contrast == .increased ? NRColor.fg3 : NRColor.hairlineSoft)
                    .frame(height: NRSpace.hairline)
            }
        }
        // The keyboard's ring (manifest §4 #7), inside the row: the card clips anything outside.
        .overlay { if isFocused { NRFocusRing(cornerRadius: 8, inset: 2) } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The row is the keyboard's stop, not its faded button: with Keyboard navigation on, Tab
        // reaches it and Space or Return does what the button does. Activate only, as the tabs
        // in the strip, so a click never leaves a ring on the row.
        .focusable(interactions: .activate)
        .focusEffectDisabled()
        .onKeyPress(.space) { perform(); return .handled }
        .onKeyPress(.return) { perform(); return .handled }
        .animation(NRMotion.animation(duration: NRMotion.fast), value: showsButton)
        // A view at opacity 0 leaves the accessibility tree, so the faded button can't be
        // relied on there, and a combined row would read differently under the pointer. The
        // row is one element with its words set here, and it carries the button's action,
        // named, and as its default.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.displayTitle(title: title, url: icon.url))
        .accessibilityValue(Self.spokenValue(host: host, jarName: jar?.name, fromJar: fromJar, when: when))
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(action)) { perform() }
        .accessibilityAction { perform() }
        .accessibilityIdentifier("smart-jar-row")   // the UI test finds the row by this and its name
    }
}

/// The row's small secondary button: "Restore" or "Open". The row carries its keyboard and
/// VoiceOver routes; this is the one for the pointer.
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
        // The row is the keyboard's stop, so Tab lands once per row, not twice.
        .focusable(false)
        .onHover { hovering = $0 }
    }
}
