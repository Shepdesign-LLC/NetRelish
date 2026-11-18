// JarFill.swift — the jar fill, the second of the app's two drips (manifest v2.1 §8 Jar fill,
// §9). Something landed in a jar: a drop in the jar's own tint falls inside it on easeDrip,
// the level rises on easeJar and overshoots before it settles, the tile bumps once, and the
// tile's count badge shows for a moment. Under Reduce Motion the level just changes and the
// badge still shows.
//
// It never decides when to play. `Workbench.fillJar(_:)` publishes `jarFill`: the Seal
// overlay calls it when the flying chip lands, and the Workbench calls it when a tab or a
// Brine row is dropped on a jar. It plays only on that change, never on appear.

import Pantry
import SwiftUI

/// What a Shelf tile shows of its jar at this moment.
struct JarFillState: Equatable {
    /// The level drawn, 0…1.
    var fill: Double
    /// The drip's drop on its way down, 0…1; nil when no drop is falling.
    var dropProgress: Double?
    /// The tile's scale: 1 at rest, 1.05 at the top of the bump.
    var bump: CGFloat
    /// The count badge is showing.
    var badgeVisible: Bool
}

/// Drives one jar's fill for its Shelf tile and hands the tile what to draw.
struct JarFillDriver<Content: View>: View {
    let jar: Jar
    let workbench: Workbench
    let content: (JarFillState) -> Content

    @Environment(\.nrReduceMotion) private var reduceMotion
    /// The level on display. Nil only before the tile first appears, when it shows the
    /// Workbench's level as it is.
    @State private var displayedFill: Double? = nil
    @State private var dropProgress: Double? = nil
    @State private var bump: CGFloat = 1
    @State private var badgeVisible = false
    /// The drip that is playing, cancelled when the next one starts.
    @State private var run: Task<Void, Never>? = nil
    @State private var badgeRun: Task<Void, Never>? = nil

    /// How long the count badge stays after something lands.
    static var badgeTime: Duration { .milliseconds(2400) }
    /// The drop's fall, and when the level starts to rise.
    static var dropTime: TimeInterval { 0.3 }
    static var riseDelay: Duration { .milliseconds(240) }
    /// The level's rise and the tile's bump.
    static var riseTime: TimeInterval { 0.42 }

    init(jar: Jar, workbench: Workbench, @ViewBuilder content: @escaping (JarFillState) -> Content) {
        self.jar = jar
        self.workbench = workbench
        self.content = content
    }

    var body: some View {
        let live = workbench.fill(of: jar)
        content(JarFillState(fill: displayedFill ?? live, dropProgress: dropProgress,
                             bump: bump, badgeVisible: badgeVisible))
            .onChange(of: workbench.jarFill) { _, event in
                guard let event, event.jarId == jar.id else { return }
                play()
            }
            .onAppear { if displayedFill == nil { displayedFill = live } }
            .onChange(of: live) { _, level in follow(level) }
            .onDisappear {
                run?.cancel()
                run = nil
                badgeRun?.cancel()
                badgeRun = nil
                badgeVisible = false
                dropProgress = nil
                bump = 1
                // Back on screen, the tile shows the jar's level as it is then.
                displayedFill = nil
            }
    }

    /// The jar's level changed with no drip playing: follow it on easeJar.
    private func follow(_ level: Double) {
        guard run == nil else { return }   // a drip is playing; it settles on the level when it ends
        if reduceMotion {
            displayedFill = level
        } else {
            withAnimation(NRMotion.animation(NRMotion.easeJar, duration: Self.riseTime)) { displayedFill = level }
        }
    }

    private func play() {
        run?.cancel()
        run = nil
        showBadge()
        let target = workbench.fill(of: jar)
        if reduceMotion {
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) {
                displayedFill = target
                dropProgress = nil
                bump = 1
            }
            return
        }
        // Seal leaves the count as it was (a tab closes and the jar keeps an item), so a
        // level already at the target rises from one item lower, or the drip shows no rise.
        let current = displayedFill ?? target
        let step = 1.0 / Double(Workbench.jarHolds)
        let start = abs(current - target) < 0.0001 ? max(0, target - step) : current
        run = Task { @MainActor in
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) {
                displayedFill = start
                dropProgress = 0
                bump = 1
            }
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }

            // The drop: born under the neck, falls to the surface on gravity.
            withAnimation(NRMotion.animation(NRMotion.easeDrip, duration: Self.dropTime)) { dropProgress = 1 }
            try? await Task.sleep(for: Self.riseDelay)
            guard !Task.isCancelled else { return }

            // The level rises on easeJar, overshoots and settles; the tile bumps once.
            let level = workbench.fill(of: jar)
            withAnimation(NRMotion.animation(NRMotion.easeJar, duration: Self.riseTime)) { displayedFill = level }
            withAnimation(NRMotion.animation(NRMotion.easeJar, duration: Self.riseTime / 2)) { bump = 1.05 }
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            dropProgress = nil

            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(NRMotion.animation(NRMotion.easeJar, duration: Self.riseTime / 2)) { bump = 1 }
            try? await Task.sleep(for: .milliseconds(210))
            guard !Task.isCancelled else { return }

            run = nil
            // Whatever the jar holds now, the tile ends on it.
            let settled = workbench.fill(of: jar)
            if displayedFill != settled {
                withAnimation(NRMotion.animation(NRMotion.easeJar, duration: Self.riseTime)) { displayedFill = settled }
            }
        }
    }

    private func showBadge() {
        badgeRun?.cancel()
        withAnimation(NRMotion.animation(duration: NRMotion.base)) { badgeVisible = true }
        badgeRun = Task { @MainActor in
            try? await Task.sleep(for: Self.badgeTime)
            guard !Task.isCancelled else { return }
            withAnimation(NRMotion.animation(duration: NRMotion.base)) { badgeVisible = false }
        }
    }
}
