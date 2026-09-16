// AssetSections.swift — DEBUG-only. Symbols, the mark, and shapes.

#if DEBUG
import SwiftUI

struct SymbolGrid: View {
    var body: some View {
        HStack(alignment: .top, spacing: NRSpace.sp8) {
            ForEach(NRSymbol.allCases, id: \.self) { symbol in
                KitCell("#\(symbol.rawValue)\nNRSymbol.\(String(describing: symbol))") {
                    HStack(alignment: .bottom, spacing: NRSpace.sp3) {
                        symbolImage(symbol, size: 24)
                        symbolImage(symbol, size: 48)
                    }
                    .frame(height: 48, alignment: .bottom)
                }
            }
        }
    }

    /// The lip stretches horizontally (`preserveAspectRatio="none"`); everything else is square.
    @ViewBuilder
    private func symbolImage(_ symbol: NRSymbol, size: CGFloat) -> some View {
        let tint = tint(for: symbol)
        if symbol == .lip {
            symbol.image.resizable().frame(width: size * 2, height: NRSpace.lipH).foregroundStyle(tint)
        } else {
            symbol.image.resizable().frame(width: size, height: size).foregroundStyle(tint)
        }
    }

    /// Manifest §7: seal, lip, and drip are relish; jars and sink are neutral.
    private func tint(for symbol: NRSymbol) -> Color {
        switch symbol {
        case .seal, .lip, .drip: NRColor.relish500
        case .jar, .jarSmart, .jarPickle, .sink: NRColor.fg
        }
    }
}

struct LogoRow: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: NRSpace.sp10) {
            KitCell("logo.svg · 16pt (titlebar)") { NRLogo.mark.image.resizable().frame(width: 16, height: 16) }
            KitCell("logo.svg · 64pt") { NRLogo.mark.image.resizable().frame(width: 64, height: 64) }
            KitCell("logo-cog.svg · 40pt (minimum)") { NRLogo.cog.image.resizable().frame(width: 40, height: 40) }
            KitCell("logo-cog.svg · 64pt (empty states)") { NRLogo.cog.image.resizable().frame(width: 64, height: 64) }
            KitCell("The squircle is Superellipse(n: 5)") {
                ZStack {
                    Superellipse().strokeBorder(NRColor.fg3, lineWidth: NRSpace.hairline).frame(width: 64, height: 64)
                    NRLogo.mark.image.resizable().frame(width: 64, height: 64).opacity(0.35)
                }
            }
        }
    }
}

struct ShapeRow: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: NRSpace.sp10) {
            KitCell("Superellipse(n: 5)") {
                Superellipse().fill(NRColor.surface2)
                    .overlay(Superellipse().strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                    .frame(width: 72, height: 72)
            }
            KitCell("Superellipse(n: 2) — an ellipse, for comparison") {
                Superellipse(n: 2).fill(NRColor.surface2)
                    .overlay(Superellipse(n: 2).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                    .frame(width: 72, height: 72)
            }
            KitCell("RoundedRectangle(r3) — what we don't use for jars") {
                RoundedRectangle(cornerRadius: NRRadius.r3).fill(NRColor.surface2)
                    .overlay(RoundedRectangle(cornerRadius: NRRadius.r3).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                    .frame(width: 72, height: 72)
            }
            KitCell("JarShape — superellipse shoulders") {
                JarShape().fill(NRColor.fg)
                    .overlay(JarShoulderLine().stroke(NRColor.bg, lineWidth: NRSpace.hairline))
                    .frame(width: 44, height: 64)
            }
            KitCell("NRJarGlyph · 24 / 48 / 96") {
                HStack(alignment: .bottom, spacing: NRSpace.sp4) {
                    NRJarGlyph(size: 24).foregroundStyle(NRColor.fg)
                    NRJarGlyph(.smart, size: 48).foregroundStyle(NRColor.fg)
                    NRJarGlyph(.pickle, size: 96).foregroundStyle(NRColor.fg)
                }
            }
        }
    }
}
#endif
