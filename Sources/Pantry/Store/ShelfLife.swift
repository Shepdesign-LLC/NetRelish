// ShelfLife.swift — when a tab sinks. Pure functions so the sweep and the UI agree.
//
// A jar's shelf life is in days (fractional allowed). A tab's life runs from the last
// time it was touched. Pinned tabs never sink (manifest §8). Over the last 10% of its
// life a tab is "fading" and the strip draws it in fg3.

import Foundation

public enum ShelfLife {
    public static let secondsPerDay: TimeInterval = 86_400

    /// The jar's shelf life in seconds; nil when the jar has none set.
    public static func seconds(for jar: Jar) -> TimeInterval? {
        guard let days = jar.shelfLifeDays, days > 0 else { return nil }
        return days * secondsPerDay
    }

    /// 1 = fresh, 0 = gone. Nil when the tab cannot sink (pinned, or the jar has no shelf life).
    public static func remaining(of tab: Tab, in jar: Jar, now: Date = Date()) -> Double? {
        guard tab.isPinned == false, let life = seconds(for: jar) else { return nil }
        let age = now.timeIntervalSince(tab.touchedAt)
        return max(0, min(1, 1 - age / life))
    }

    public static func shouldSink(_ tab: Tab, in jar: Jar, now: Date = Date()) -> Bool {
        remaining(of: tab, in: jar, now: now) == 0
    }

    /// Last 10% of life: the strip fades the tab.
    public static func isFading(_ tab: Tab, in jar: Jar, now: Date = Date()) -> Bool {
        guard let r = remaining(of: tab, in: jar, now: now) else { return false }
        return r > 0 && r < 0.1
    }

    /// The tabs that are fading, across every jar, the one closest to sinking first. The
    /// strip fades exactly these, so the Sinking soon jar and the tab strip always agree.
    public static func sinkingSoon(_ tabs: [Tab], jars: [Jar], now: Date = Date()) -> [Tab] {
        let byId = Dictionary(jars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tabs
            .compactMap { tab -> (tab: Tab, left: TimeInterval)? in
                guard let jar = tab.jarId.flatMap({ byId[$0] }), isFading(tab, in: jar, now: now),
                      let left = timeLeft(of: tab, in: jar, now: now) else { return nil }
                return (tab, left)
            }
            .sorted { $0.left < $1.left }
            .map { $0.tab }
    }

    /// Seconds until the tab sinks; nil when it can't.
    public static func timeLeft(of tab: Tab, in jar: Jar, now: Date = Date()) -> TimeInterval? {
        guard let r = remaining(of: tab, in: jar, now: now), let life = seconds(for: jar) else { return nil }
        return r * life
    }
}
