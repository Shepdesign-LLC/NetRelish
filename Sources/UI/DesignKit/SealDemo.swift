// SealDemo.swift — DEBUG-only. The Seal animation, manifest §8 + §9.
// Glyph pulses once → the drip falls (NRMotion.seal, easeJar) → the tab closes →
// the jar's badge increments. Under Reduce Motion every step is a fade.
// This is the ONE drip in the app and the only animation longer than NRMotion.base.

#if DEBUG
import SwiftUI

struct SealDemo: View {
    /// Increment to run the animation.
    var trigger: Int

    @Environment(\.nrReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var dripVisible = false
    @State private var dripFallen = false
    @State private var tabOpen = true
    @State private var count = 411
    @State private var run: Task<Void, Never>?

    private let dripDistance: CGFloat = 56

    var body: some View {
        VStack(spacing: NRSpace.sp3) {
            // The tab being sealed.
            ZStack(alignment: .top) {
                HStack(spacing: NRSpace.sp2) {
                    Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(NRColor.fg3)
                    Text("Invoice terms — kickoff notes").font(NRType.font(NRType.fsSm, weight: .medium)).foregroundStyle(NRColor.fg).lineLimit(1)
                    Spacer()
                    NRSymbol.seal.image.resizable().frame(width: 16, height: 16)
                        .foregroundStyle(NRColor.relish500)
                        .scaleEffect(pulse && !reduceMotion ? 1.25 : 1)
                        .opacity(pulse && reduceMotion ? 0.5 : 1)
                }
                .padding(.horizontal, NRSpace.sp3)
                .frame(width: 260, height: NRSpace.tabH)
                .background(NRColor.surface, in: UnevenRoundedRectangle(topLeadingRadius: NRRadius.r2, topTrailingRadius: NRRadius.r2))
                .overlay(alignment: .top) { NRTabLip().padding(.horizontal, NRSpace.sp2) }
                .opacity(tabOpen ? 1 : 0)
                .scaleEffect(tabOpen || reduceMotion ? 1 : 0.96, anchor: .top)
            }
            .frame(height: NRSpace.tabH)

            // The drip's lane, then the jar it lands in.
            ZStack(alignment: .top) {
                Color.clear.frame(width: 260, height: dripDistance + 8)
                NRSymbol.drip.image.resizable().frame(width: 14, height: 14)
                    .foregroundStyle(NRColor.relish500)
                    .offset(y: (dripFallen && !reduceMotion) ? dripDistance : 0)
                    .opacity(dripVisible ? (dripFallen ? 0 : 1) : 0)
            }
            HStack(spacing: NRSpace.sp2) {
                NRJarGlyph(size: 32).foregroundStyle(NRColor.fg)
                Text("Meridian").font(NRType.font(NRType.fsMd, weight: .medium)).foregroundStyle(NRColor.fg)
                NRBadge("\(count) preserved")
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 280)
        .padding(NRSpace.sp3)
        .background(NRColor.surface2, in: RoundedRectangle(cornerRadius: NRRadius.r2))
        .onChange(of: trigger) { _, _ in seal() }
        .onTapGesture { seal() }
        .help("Click, or ⌘S, to run the Seal animation")
    }

    private func seal() {
        run?.cancel()
        let reduce = reduceMotion
        run = Task { @MainActor in
            // Reset instantly if a previous run left the tab closed.
            withAnimation(.linear(duration: 0)) { tabOpen = true; dripVisible = false; dripFallen = false; pulse = false }
            try? await Task.sleep(for: .milliseconds(16))

            // 1. The glyph pulses once (t-base, ease-out).
            withAnimation(NRMotion.animation(NRMotion.easeOut, duration: NRMotion.base / 2)) { pulse = true }
            try? await Task.sleep(for: .seconds(NRMotion.base / 2))
            withAnimation(NRMotion.animation(NRMotion.easeOut, duration: NRMotion.base / 2)) { pulse = false }
            guard !Task.isCancelled else { return }

            // 2. The drip falls (t-seal, ease-jar). Reduce Motion: it fades in place.
            withAnimation(.linear(duration: 0)) { dripVisible = true }
            withAnimation(NRMotion.animation(reduce ? NRMotion.easeOut : NRMotion.easeJar, duration: NRMotion.seal)) { dripFallen = true }
            try? await Task.sleep(for: .seconds(NRMotion.seal))
            guard !Task.isCancelled else { return }

            // 3. The tab closes (t-base) and the badge increments.
            withAnimation(NRMotion.animation(NRMotion.easeOut, duration: NRMotion.base)) {
                tabOpen = false
                count += 1
            }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }

            // Demo only: bring the tab back so it can be sealed again.
            withAnimation(NRMotion.animation(NRMotion.easeOut, duration: NRMotion.base)) { tabOpen = true }
            dripVisible = false
            dripFallen = false
        }
    }
}
#endif
