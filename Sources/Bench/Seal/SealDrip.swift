// SealDrip.swift — the one drip in the app (manifest §9). It runs when `trigger` changes:
// the seal glyph pulses once, the drip falls toward the Shelf on NRMotion.seal with easeJar,
// and fades out. Under Reduce Motion every step is a fade with no travel.
//
// It sits in an overlay above the Bench and never takes a click: the seal itself is already
// underway in the Pantry while this plays.

import SwiftUI

struct SealDrip: View {
    var trigger: Int

    @Environment(\.nrReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var visible = false
    @State private var fallen = false
    @State private var run: Task<Void, Never>?

    /// Far enough to read as "into the Shelf" without chasing the jar's exact position.
    private let distance: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if visible {
                NRSymbol.seal.image.resizable().frame(width: 20, height: 20)
                    .foregroundStyle(NRColor.relish500)
                    .scaleEffect(pulse && !reduceMotion ? 1.25 : 1)
                    .opacity(pulse ? 1 : 0)
                NRSymbol.drip.image.resizable().frame(width: 14, height: 14)
                    .foregroundStyle(NRColor.relish500)
                    .offset(x: 3, y: (fallen && !reduceMotion) ? distance : 0)
                    .opacity(fallen ? 0 : (visible ? 1 : 0))
            }
        }
        .frame(width: 24, height: distance + 24, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, new in if new > 0 { play() } }
    }

    private func play() {
        run?.cancel()
        let reduce = reduceMotion
        run = Task { @MainActor in
            withAnimation(.linear(duration: 0)) { visible = true; fallen = false; pulse = false }
            try? await Task.sleep(for: .milliseconds(16))

            withAnimation(NRMotion.animation(NRMotion.easeOut, duration: NRMotion.base / 2)) { pulse = true }
            try? await Task.sleep(for: .seconds(NRMotion.base / 2))
            guard !Task.isCancelled else { return }

            withAnimation(NRMotion.animation(reduce ? NRMotion.easeOut : NRMotion.easeJar, duration: NRMotion.seal)) {
                fallen = true
                pulse = false
            }
            try? await Task.sleep(for: .seconds(NRMotion.seal))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}
