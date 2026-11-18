// SealOverlay.swift — the window's one Seal overlay (manifest v2.1 §9, ADR 0035, the facelift
// comp's MOTION notes). Seal shows in two phases:
//
//   A, on the key press (`SealPhase.started`): the glyph pulses, the front tab's lip rises to
//      the window's top edge, a relish band runs out of it along the top of the tab strip,
//      and drops form and HANG while the page freezes.
//   B, when the write returns (`.frozen` / `.failed`), never earlier than 700ms after A
//      started: the page blinks, the Sealed pill lands, the band drains back to the lip, and
//      a chip of the tab flies to its jar on the Shelf, which fills. A failure only drains.
//
// Workbench decides when B starts; nothing here waits on a timer to decide it. The sleeps
// only pace the presentation, and every effect of Seal (non-negotiable 3) has already happened
// when they run: the tab closed when the write returned, and the strip draws a picture of it
// (`Workbench.stripTabs`) until the chip leaves.
//
// Each frame is a pure function of the clock: the run's Task records when things start, and a
// TimelineView draws the band, the drops, the pill and the chip from those instants on the
// token curves. Nothing is drawn, and no timeline runs, while no Seal is playing.
//
// Under Reduce Motion, Seal is a fade: the glyph dims, the pill fades in, the jar's level
// changes plainly. Seal from Shortcuts with no window, or into a window that isn't active,
// plays nothing. Hand-written.

import Pantry
import SwiftUI

struct SealOverlay: View {
    @Bindable var workbench: Workbench
    let rects: [SealAnchorRole: CGRect]
    let size: CGSize

    @Environment(\.nrReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    /// The run this overlay is presenting, and what it has done with it so far.
    @State private var current: SealCurrent?
    /// What the run draws, worked out once from the anchors when it started. Nil: nothing drawn.
    @State private var scene: SealScene?
    /// When each part of the run started.
    @State private var clock: SealClock?
    /// The drops have formed and are hanging: the timeline pauses until phase B.
    @State private var hanging = false
    /// The run's presentation, one Task at a time.
    @State private var task: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let scene, let clock {
                TimelineView(.animation(minimumInterval: nil, paused: hanging)) { context in
                    SealFrame(scene: scene, clock: clock, now: context.date)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onChange(of: workbench.sealPhase) { _, phase in
            switch phase {
            case .idle:
                return
            case .started(let run):
                begin(run)
            case .frozen(let run):
                finish(run, frozen: true)
            case .failed(let run):
                finish(run, frozen: false)
            }
        }
        .onDisappear {
            // Workbench's own 4-second safety lets go of the held tab and goes back to idle.
            task?.cancel()
            task = nil
            if let current, !current.silent { SealPresenters.playing.remove(current.run.id) }
            current = nil
            clear()
        }
    }

    // MARK: Phase A

    private func begin(_ run: SealRun) {
        if let old = current, old.run.id != run.id { land(old) }
        task?.cancel()
        task = nil
        clear()

        guard appearsActive, let built = SealScene.make(run: run, rects: rects, width: size.width,
                                                       reduceMotion: reduceMotion) else {
            // Not this window's to show: play nothing, and let go at phase B unless another
            // window is presenting it.
            current = SealCurrent(run: run, silent: true)
            return
        }
        current = SealCurrent(run: run, silent: false)
        SealPresenters.playing.insert(run.id)
        scene = built
        clock = SealClock(aStart: Date())
        let runId = run.id
        task = Task { @MainActor in
            // The longest drop has formed by ~0.92s (t200 + 3×40 + 480 + a little); after that
            // nothing moves until the write returns, so the timeline can rest.
            try? await Task.sleep(for: .milliseconds(960))
            guard !Task.isCancelled, current?.run.id == runId, clock?.bAt == nil else { return }
            hanging = true
        }
    }

    // MARK: Phase B

    private func finish(_ run: SealRun, frozen: Bool) {
        guard let playing = current, playing.run.id == run.id else {
            // A run this overlay never saw start (the write returned before a frame was drawn):
            // nothing to animate. The active window still lands it, once.
            if frozen, appearsActive {
                workbench.releaseSealedTab(run.id)
                workbench.fillJar(run.jarId)
                workbench.sealPresentationEnded(run.id)
            }
            return
        }
        if playing.silent {
            current = nil
            // One Workbench serves every window: the window that presents this run lets go of
            // it when its chip leaves. With none presenting it (Seal from Shortcuts while
            // NetRelish is in the background), the tab goes from the strip at once.
            if !SealPresenters.playing.contains(run.id) {
                workbench.releaseSealedTab(run.id)
                workbench.sealPresentationEnded(run.id)
            }
            return
        }
        current?.frozen = frozen
        task?.cancel()

        let reduce = scene?.reduceMotion ?? reduceMotion
        let begins = max(Date(), run.startedAt.addingTimeInterval(SealTiming.minimumA))
        let page = rects[.page]
        let jar = rects[.jar(run.jarId)]
        let shelf = rects[.shelfJars]
        let runId = run.id

        task = Task { @MainActor in
            let wait = begins.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, current?.run.id == runId else { return }
            hanging = false
            clock?.bAt = Date()
            clock?.frozen = frozen
            clock?.page = page

            guard frozen else {
                // Failure: the drops drain, no pill; the field already says it couldn't seal.
                if !reduce { try? await Task.sleep(for: .seconds(SealTiming.failClear)) }
                guard !Task.isCancelled, current?.run.id == runId else { return }
                endRun(runId)
                return
            }

            if reduce {
                try? await Task.sleep(for: .seconds(SealTiming.reduceHold))
                guard !Task.isCancelled, current?.run.id == runId else { return }
                workbench.releaseSealedTab(runId)
                landRun(runId)
                return
            }

            try? await Task.sleep(for: .seconds(SealTiming.chipLeaves))
            guard !Task.isCancelled, current?.run.id == runId else { return }
            // The last place the tab was drawn, read before the strip lets go of it.
            let from = scene?.tab
            workbench.releaseSealedTab(runId)
            guard let from, let jar else {
                landRun(runId)
                return
            }
            clock?.chipFrom = from
            clock?.chipTo = SealScene.chipLanding(on: jar, within: shelf)
            clock?.chipAt = Date()
            try? await Task.sleep(for: .seconds(SealTiming.chipFlight))
            guard !Task.isCancelled, current?.run.id == runId else { return }
            landRun(runId)
        }
    }

    /// The chip reached its jar (or there was nowhere to fly): the jar fills and the run ends.
    private func landRun(_ runId: Int) {
        guard let playing = current, playing.run.id == runId else { return }
        current?.landed = true
        workbench.fillJar(playing.run.jarId)
        endRun(runId)
    }

    private func endRun(_ runId: Int) {
        guard current?.run.id == runId else { return }
        task = nil
        current = nil
        clear()
        SealPresenters.playing.remove(runId)
        workbench.sealPresentationEnded(runId)
    }

    /// A second Seal while this one plays: jump to its end state now. A run that was frozen
    /// and hadn't landed lands (the tab is let go and its jar fills); one still freezing
    /// gets its fill from Workbench when its write returns.
    private func land(_ old: SealCurrent) {
        task?.cancel()
        task = nil
        if old.frozen == true, !old.landed, !old.silent {
            workbench.releaseSealedTab(old.run.id)
            workbench.fillJar(old.run.jarId)
        }
        if !old.silent { SealPresenters.playing.remove(old.run.id) }
        workbench.sealPresentationEnded(old.run.id)
        current = nil
        clear()
    }

    private func clear() {
        scene = nil
        clock = nil
        hanging = false
    }
}

// MARK: - Timings (the comp's, in seconds)

enum SealTiming {
    /// Phase B never starts sooner than this after A.
    static let minimumA: TimeInterval = 0.7
    /// After B starts.
    static let pillAt: TimeInterval = 0.02
    static let drainAt: TimeInterval = 0.28
    static let chipLeaves: TimeInterval = 0.64
    static let chipFlight: TimeInterval = 0.56
    static let failClear: TimeInterval = 0.48
    /// Reduce Motion: the pill holds this long before the run ends.
    static let reduceHold: TimeInterval = 0.7
}

// MARK: - State

/// The runs a window is presenting right now. Every window has its own overlay over one shared
/// Workbench; a window that plays nothing leaves a run alone while another window presents it.
@MainActor
private enum SealPresenters {
    static var playing: Set<Int> = []
}

/// The run an overlay is presenting.
private struct SealCurrent {
    let run: SealRun
    let silent: Bool
    var frozen: Bool?
    var landed = false

    init(run: SealRun, silent: Bool) {
        self.run = run
        self.silent = silent
    }
}

/// When each part of a run started, and the places phase B reads.
private struct SealClock: Equatable {
    var aStart: Date
    var bAt: Date?
    var frozen = false
    var page: CGRect?
    var chipFrom: CGRect?
    var chipTo: CGPoint?
    var chipAt: Date?

    init(aStart: Date) { self.aStart = aStart }
}

/// One drop on the band.
struct SealDrop: Equatable {
    let cx: CGFloat
    let w: CGFloat
    let length: CGFloat
    let big: Bool
    var order = 0     // its place outward from the tab's center: the stagger
}

/// What one run draws, worked out from the anchors when it starts.
struct SealScene: Equatable {
    let run: SealRun
    let reduceMotion: Bool
    let tab: CGRect
    let slot: CGRect?
    let bandTop: CGFloat
    let bandLeft: CGFloat
    let bandRight: CGFloat
    let lipLeft: CGFloat
    let lipRight: CGFloat
    let connBottom: CGFloat
    let drops: [SealDrop]

    /// The band's height. Drops hang from its bottom edge; the biggest one's tip stops 50pt
    /// under the strip's top, above the address field.
    static let bandH: CGFloat = 14

    /// Nil when the front tab isn't drawn in this window: nothing to play from.
    static func make(run: SealRun, rects: [SealAnchorRole: CGRect], width: CGFloat,
                     reduceMotion: Bool) -> SealScene? {
        guard let tab = rects[.tab(run.tab.id)], tab.width > 8 else { return nil }
        let strip = rects[.tabStrip] ?? CGRect(x: max(0, tab.minX - 8), y: 0,
                                               width: max(0, width - tab.minX + 8), height: NRShell.titleH)
        let bandTop = strip.minY
        let bandLeft = strip.minX + 8
        let bandRight = width + 8
        let drops = reduceMotion ? [] : Self.drops(run: run, tab: tab, strip: strip, newTab: rects[.newTab],
                                                    bandLeft: bandLeft, width: width, rects: rects)
        return SealScene(run: run, reduceMotion: reduceMotion, tab: tab, slot: rects[.sealSlot],
                         bandTop: bandTop, bandLeft: bandLeft, bandRight: bandRight,
                         lipLeft: tab.minX + 4, lipRight: tab.maxX - 4,
                         connBottom: max(tab.minY + 6, bandTop + 2), drops: drops)
    }

    /// Where the flying chip lands: on the jar's shoulder, `(midX − 8, minY + 4)`. A jar
    /// scrolled out of the Shelf's column still has a rect, off the visible rail; the landing
    /// is then held inside the part of the column on screen, so the chip never flies to a
    /// point nobody can see.
    static func chipLanding(on jar: CGRect, within shelf: CGRect?) -> CGPoint {
        let target = CGPoint(x: jar.midX - 8, y: jar.minY + 4)
        guard let shelf, shelf.height > 24 else { return target }
        return CGPoint(x: target.x, y: min(max(target.y, shelf.minY + 4), shelf.maxY - 20))
    }

    /// Where drops may fall, the comp's `sealDrops`: never on the window buttons, never across
    /// a tab's title.
    private static func drops(run: SealRun, tab: CGRect, strip: CGRect, newTab: CGRect?,
                              bandLeft: CGFloat, width: CGFloat,
                              rects: [SealAnchorRole: CGRect]) -> [SealDrop] {
        var tabs: [CGRect] = []
        for (role, rect) in rects {
            if case .tab = role, rect.maxX > strip.minX, rect.minX < strip.maxX { tabs.append(rect) }
        }
        tabs.sort { $0.minX < $1.minX }

        var drops: [SealDrop] = []
        // 1) the nub on the lip, about 68% across (centered on a pinned tab): short, above the title
        let pinned = run.tab.isPinned
        drops.append(SealDrop(cx: tab.minX + tab.width * (pinned ? 0.5 : 0.68), w: pinned ? 11 : 14,
                              length: 6, big: false))
        // 2) small drops on the seams between tabs, where only rounded corners sit underneath
        var seams: [CGFloat] = []
        if tabs.count >= 2 {
            for i in 0..<(tabs.count - 1) {
                let seam = (tabs[i].maxX + tabs[i + 1].minX) / 2
                if abs(seam - tab.midX) > tab.width / 2 + 16 { seams.append(seam) }
            }
        }
        let picked: [CGFloat] = seams.count <= 3 ? seams : [0.0, 0.5, 1.0].map { f in
            seams[min(seams.count - 1, Int((f * Double(seams.count - 1)).rounded()))]
        }
        for seam in picked { drops.append(SealDrop(cx: seam, w: 13, length: 10, big: false)) }
        // 3) the big drops, where nothing sits under them: the open strip after "+"
        let openL = max(bandLeft, (newTab?.maxX ?? strip.maxX) + 12)
        let openR = width - 16
        let span = openR - openL
        if span >= 48 {
            // the one drop allowed past the strip: its tip stops above the field
            drops.append(SealDrop(cx: openL + min(span * 0.34, span - 24), w: 38, length: 36, big: true))
            if span >= 120 { drops.append(SealDrop(cx: openL + span * 0.84, w: 24, length: 20, big: true)) }
        }
        // stagger outward from the tab's center
        let order = drops.indices.sorted { abs(drops[$0].cx - tab.midX) < abs(drops[$1].cx - tab.midX) }
        for (k, index) in order.enumerated() { drops[index].order = k }
        return drops
    }
}

// MARK: - One frame

/// Everything the overlay draws at one instant. Pure: the same scene, clock and time always
/// draw the same frame.
private struct SealFrame: View {
    let scene: SealScene
    let clock: SealClock
    let now: Date

    @Environment(\.colorScheme) private var colorScheme

    private var a: Double { now.timeIntervalSince(clock.aStart) }
    private var b: Double? { clock.bAt.map { now.timeIntervalSince($0) } }
    private var reduce: Bool { scene.reduceMotion }
    /// When the drain starts, after B: a sealed page shows its pill first; a failure drains at once.
    private var drainAt: Double { clock.frozen ? SealTiming.drainAt : 0 }
    /// 0 → 1 over `duration`, starting `delay` after the drain starts, on easeOut. 0 before B.
    private func drain(after delay: Double, duration: Double) -> Double {
        guard let b else { return 0 }
        return sealEase(NRMotion.easeOut, (b - drainAt - delay) / duration)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if reduce {
                reducedSlot
                if clock.frozen, let b { pill(at: b) }
            } else {
                pageBlink
                band
                drops
                slotCover
                if clock.frozen, let b, b >= SealTiming.pillAt, b < SealTiming.chipLeaves + 0.16 { pill(at: b) }
                chip
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Page

    @ViewBuilder private var pageBlink: some View {
        if clock.frozen, let b, b < 0.16, let page = clock.page {
            let p = sealEase(NRMotion.easeOut, b / 0.16)
            let ink: Double = p < 0.5 ? 0.07 * p / 0.5 : 0.07 * (1 - (p - 0.5) / 0.5)
            Rectangle()
                .fill(NRColor.fg)
                .opacity(ink)
                .frame(width: page.width, height: page.height)
                .offset(x: page.minX, y: page.minY)
        }
    }

    // MARK: The lip, the band and its highlight

    @ViewBuilder private var band: some View {
        let ended: Bool = b.map { $0 >= drainAt + 0.36 } ?? false
        if !ended {
            // t60: the lip rises to the strip's top; the drain lowers it again.
            let rise: Double = sealEase(NRMotion.easeOut, (a - 0.06) / 0.12) * (1 - drain(after: 0.22, duration: 0.14))
            if rise > 0.001 {
                let top: CGFloat = scene.connBottom - (scene.connBottom - scene.bandTop) * CGFloat(rise)
                SealRectShape(rect: CGRect(x: scene.lipLeft, y: top,
                                           width: max(0, scene.lipRight - scene.lipLeft),
                                           height: scene.connBottom - top), radius: 0)
                    .fill(NRColor.relish500)
            }
            // t120: the band runs out of the lip, both ways; the drain draws it back to the lip's
            // own width over 3/4 of 320ms, and it fades in the last quarter.
            let grow = sealEase(NRMotion.easeOut, (a - 0.12) / 0.26)
            let q = drain(after: 0.04, duration: 0.32)
            let back: Double = q < 0.75 ? 1 - q / 0.75 : 0
            let reach: Double = min(grow, back)
            let fade: Double = q < 0.75 ? 1 : max(0, 1 - (q - 0.75) / 0.25)
            if a >= 0.12, fade > 0.001 {
                let left = sealLerp(scene.lipLeft, scene.bandLeft, reach)
                let right = sealLerp(scene.lipRight, scene.bandRight, reach)
                SealRectShape(rect: CGRect(x: left, y: scene.bandTop, width: max(0, right - left),
                                           height: SealScene.bandH),
                              radius: SealScene.bandH / 2)
                    .fill(NRColor.relish500)
                    .opacity(fade)
                // The highlight leaves first, so the drain is one flat shape.
                let lit: Bool = b.map { $0 < drainAt } ?? true
                if lit, right - left > 24 {
                    SealRectShape(rect: CGRect(x: left + 8, y: scene.bandTop + 2, width: right - left - 16,
                                               height: 2.5), radius: 1.25)
                        .fill(NRColor.relish300)
                }
            }
        }
    }

    // MARK: Drops

    private var drops: some View {
        ForEach(scene.drops.indices, id: \.self) { index in
            dropView(scene.drops[index])
        }
    }

    @ViewBuilder private func dropView(_ drop: SealDrop) -> some View {
        let state = dropState(drop)
        SealDropShape(cx: drop.cx, w: drop.w, length: drop.length,
                      top: scene.bandTop + SealScene.bandH - 0.5,
                      formation: state.formation, squeeze: state.squeeze)
            .fill(NRColor.relish500)
        if drop.big, state.gloss > 0.001 {
            SealRectShape(rect: CGRect(x: drop.cx - drop.w * 0.24, y: scene.bandTop + SealScene.bandH + 8,
                                       width: drop.w > 30 ? 4 : 3, height: drop.length * 0.42),
                          radius: 2)
                .fill(NRColor.relish300)
                .opacity(state.gloss)
        }
    }

    /// A drop at this instant: formed on easeDrip to 1.08 over its first 70%, settled on
    /// easeJar; retracted by the drain, in reverse order, 20ms apart. Big drops' gloss fades in
    /// over their last 160ms and leaves with the highlight.
    private func dropState(_ drop: SealDrop) -> (formation: Double, squeeze: Double, gloss: Double) {
        let delay = 0.2 + Double(drop.order) * 0.04
        let duration = drop.big ? NRMotion.seal : 0.34
        let u = sealClamp((a - delay) / duration)
        let formed: Double = u < 0.7 ? 1.08 * sealEase(NRMotion.easeDrip, u / 0.7)
                                     : 1.08 - 0.08 * sealEase(NRMotion.easeJar, (u - 0.7) / 0.3)
        let retract = drain(after: Double(scene.drops.count - 1 - drop.order) * 0.02, duration: 0.24)
        let squeeze = 0.85 + 0.15 * sealEase(NRMotion.easeDrip, min(1, u / 0.7))
        let shown = sealClamp((a - (delay + duration - 0.16)) / 0.16)
        let gone: Double = b.map { sealClamp(($0 - drainAt) / 0.1) } ?? 0
        return (formed * (1 - retract), squeeze, drop.big ? shown * (1 - gone) : 0)
    }

    // MARK: The Seal slot

    /// Covers the address row's Seal glyph with its own copy, so it can pulse and give way to
    /// the pill, whatever the slot under it shows once the tab has closed.
    @ViewBuilder private var slotCover: some View {
        if let slot = scene.slot {
            let pulse = sealEase(NRMotion.easeOut, a / 0.2)
            let rising: Double = pulse < 0.5 ? 1 + 0.18 * pulse / 0.5 : 1.18 - 0.18 * (pulse - 0.5) / 0.5
            let scale: Double = a < 0.2 ? rising : 1
            let sinceB: Double = b ?? -1
            let glyph: Double = clock.frozen ? 1 - sealClamp((sinceB - SealTiming.pillAt) / 0.12) : 1
            let cover: Double = 1 - sealClamp((sinceB - SealTiming.chipLeaves) / 0.16)
            if cover > 0.001 {
                ZStack {
                    Rectangle().fill(NRColor.surface)
                    NRSymbol.seal.image.resizable()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(NRColor.relish500)
                        .scaleEffect(CGFloat(scale))
                        .opacity(glyph)
                }
                .frame(width: slot.width, height: slot.height)
                .opacity(cover)
                .offset(x: slot.minX, y: slot.minY)
            }
        }
    }

    /// Reduce Motion: the glyph dims while the page freezes, and gives way to the pill.
    @ViewBuilder private var reducedSlot: some View {
        if let slot = scene.slot {
            let dim: Double = 1 - 0.55 * sealClamp(a / 0.12)
            let sinceB: Double = b ?? -1
            let glyph: Double = clock.frozen ? dim * (1 - sealClamp(sinceB / 0.16)) : dim
            ZStack {
                Rectangle().fill(NRColor.surface)
                NRSymbol.seal.image.resizable()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(NRColor.relish500)
                    .opacity(glyph)
            }
            .frame(width: slot.width, height: slot.height)
            .offset(x: slot.minX, y: slot.minY)
        }
    }

    // MARK: The Sealed pill

    @ViewBuilder private func pill(at b: Double) -> some View {
        if let slot = scene.slot {
            let lane: CGFloat = 220
            let look = pillLook(at: b)
            NRSealedPill(size: .regular, checkProgress: look.check)
                .background(Capsule().fill(NRColor.surface).padding(-2))
                .scaleEffect(look.scale, anchor: .trailing)
                .opacity(look.opacity)
                .frame(width: lane, height: slot.height, alignment: .trailing)
                .offset(x: slot.maxX - lane, y: slot.minY)
        }
    }

    /// The pill pops on easeJar (0.6 → 1.04 → 1, fading in), its check draws on from 140ms,
    /// and it leaves with the tab's chip. Under Reduce Motion it only fades in.
    private func pillLook(at b: Double) -> (scale: CGFloat, opacity: Double, check: Double) {
        if reduce { return (1, sealClamp(b / 0.2), 1) }
        let p = sealEase(NRMotion.easeJar, (b - SealTiming.pillAt) / 0.32)
        let scale: Double = p < 0.6 ? 0.6 + 0.44 * p / 0.6 : 1.04 - 0.04 * (p - 0.6) / 0.4
        let fadeIn = sealClamp(p / 0.6)
        let fadeOut = 1 - sealClamp((b - SealTiming.chipLeaves) / 0.16)
        return (CGFloat(scale), fadeIn * fadeOut, sealEase(NRMotion.easeOut, (b - 0.16) / 0.18))
    }

    // MARK: The chip that flies to the jar

    @ViewBuilder private var chip: some View {
        if let from = clock.chipFrom, let to = clock.chipTo, let at = clock.chipAt {
            let t = sealClamp(now.timeIntervalSince(at) / SealTiming.chipFlight)
            let x0 = from.minX + 4, y0 = from.minY + 4
            // y drops out of the strip first, so the chip never crosses the window buttons; x
            // eases in and out; it shrinks and fades late.
            let x = sealLerp(x0, to.x, sealEase(SealCurve.chipX, t))
            let y = sealLerp(y0, to.y, sealEase(NRMotion.easeOut, t))
            let late: Double = sealEase(SealCurve.chipShrink, t)
            SealChip(run: scene.run, dark: colorScheme == .dark)
                .scaleEffect(CGFloat(1 - 0.6 * late), anchor: .topLeading)
                .opacity(1 - late)
                .offset(x: x, y: y)
        }
    }
}

/// The tab, small: its icon, its title (24 characters at most) and a check.
private struct SealChip: View {
    let run: SealRun
    let dark: Bool

    private var title: String {
        let full = (run.tab.title?.isEmpty == false ? run.tab.title : run.tab.url) ?? "New Tab"
        return full.count > 24 ? String(full.prefix(23)) + "…" : full
    }

    var body: some View {
        HStack(spacing: 8) {
            TabIcon(tab: run.tab, glyph: run.glyph, size: 14)
            Text(title)
                .font(NRType.font(NRType.fsSm, weight: .medium))
                .foregroundStyle(NRColor.fg2)
                .lineLimit(1)
                .fixedSize()
            Circle()
                .fill(NRColor.relish500)
                .frame(width: 14, height: 14)
                .overlay {
                    SealCheckShape()
                        .stroke(dark ? NRColor.relishInk : Color.black,
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 9, height: 9)
                }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9).fill(NRColor.float))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
        // the float shadow in light; in dark the hairline carries it (manifest v2.1 §6)
        .shadow(color: .black.opacity(dark ? 0 : 0.08), radius: 10, y: 4)
        .shadow(color: .black.opacity(dark ? 0 : 0.04), radius: 1.5, y: 1)
        .fixedSize()
    }
}

// MARK: - Shapes and curves

/// A rounded rectangle at an absolute place in the overlay.
struct SealRectShape: Shape {
    var rect: CGRect
    var radius: CGFloat

    func path(in bounds: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let r = min(radius, rect.width / 2, rect.height / 2)
        return r > 0 ? Path(roundedRect: rect, cornerRadius: r, style: .circular) : Path(rect)
    }
}

/// One drop hanging from the band: the comp's `dropPath`, flared into the band at its top, a
/// round tip at its bottom. `formation` stretches it down from its top (0 → none, 1 → formed);
/// `squeeze` narrows it while it falls.
struct SealDropShape: Shape {
    var cx: CGFloat
    var w: CGFloat
    var length: CGFloat
    var top: CGFloat
    var formation: Double
    var squeeze: Double = 1

    var animatableData: Double {
        get { formation }
        set { formation = newValue }
    }

    func path(in bounds: CGRect) -> Path {
        guard formation > 0.001, w > 0 else { return Path() }
        let f = w * 0.55, r = w * 0.36, y = top
        let anchorY = y - 1
        let sx = CGFloat(squeeze), sy = CGFloat(formation)
        func p(_ x: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: cx + (x - cx) * sx, y: anchorY + (py - anchorY) * sy)
        }
        let left = cx - w / 2, right = cx + w / 2
        let tipY = y + length - r       // the center of the round tip
        let k = r * 0.5523
        var path = Path()
        path.move(to: p(left - f, y - 1))
        path.addCurve(to: p(left, y + f), control1: p(left, y - 1), control2: p(left, y + f * 0.55))
        path.addLine(to: p(cx - r, tipY))
        path.addCurve(to: p(cx, tipY + r), control1: p(cx - r, tipY + k), control2: p(cx - k, tipY + r))
        path.addCurve(to: p(cx + r, tipY), control1: p(cx + k, tipY + r), control2: p(cx + r, tipY + k))
        path.addLine(to: p(right, y + f))
        path.addCurve(to: p(right + f, y - 1), control1: p(right, y + f * 0.55), control2: p(right, y - 1))
        path.closeSubpath()
        return path
    }
}

/// The two curves the chip's flight uses that aren't tokens (the comp's).
private enum SealCurve {
    static let chipX = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.45, y: 0), endControlPoint: UnitPoint(x: 0.55, y: 1))
    static let chipShrink = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.55, y: 0), endControlPoint: UnitPoint(x: 0.85, y: 0.4))
}

private func sealClamp(_ x: Double) -> Double { min(1, max(0, x)) }

/// A curve's value at `progress`, clamped to 0…1 first. An overshooting curve (easeJar) can
/// still return a little over 1.
private func sealEase(_ curve: UnitCurve, _ progress: Double) -> Double {
    curve.value(at: sealClamp(progress))
}

private func sealLerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
