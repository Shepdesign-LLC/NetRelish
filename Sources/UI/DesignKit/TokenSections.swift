// TokenSections.swift — DEBUG-only. Renders every token from NRTokenCatalog.

#if DEBUG
import SwiftUI

// MARK: - Color

struct ColorTokens: View {
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: NRSpace.sp3, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: NRSpace.sp3) {
            ForEach(NRTokenCatalog.colors, id: \.css) { entry in
                HStack(spacing: NRSpace.sp3) {
                    RoundedRectangle(cornerRadius: NRRadius.r1)
                        .fill(entry.color)
                        .frame(width: 44, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NRColor.\(entry.swift)").font(NRType.font(NRType.fsSm, weight: .medium)).foregroundStyle(NRColor.fg)
                        Text(entry.css).font(NRType.font(NRType.fsXs, design: NRType.fontMono)).foregroundStyle(NRColor.fg2)
                        ResolvedHex(color: entry.color)
                    }
                }
            }
        }
    }
}

/// The sRGB hex a token resolves to in the *current* appearance — proof the dynamic color flips.
struct ResolvedHex: View {
    let color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(hex).font(NRType.font(NRType.fsXs, design: NRType.fontMono)).foregroundStyle(NRColor.fg3)
    }

    private var hex: String {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        var s = ""
        appearance.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
            s = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        }
        return s
    }
}

// MARK: - Space / Radius

struct SpaceTokens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            ForEach(NRTokenCatalog.space, id: \.css) { entry in
                HStack(spacing: NRSpace.sp3) {
                    Text("NRSpace.\(entry.swift)").font(NRType.font(NRType.fsSm, design: NRType.fontMono)).foregroundStyle(NRColor.fg).frame(width: 170, alignment: .leading)
                    Rectangle().fill(NRColor.fg3).frame(width: min(spaceValue(entry), 240), height: 8)
                    Text(entry.value).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
                }
            }
        }
    }

    private func spaceValue(_ e: NRTokenCatalog.ScalarEntry) -> CGFloat {
        CGFloat(Double(e.value.replacingOccurrences(of: "px", with: "")) ?? 0)
    }
}

struct RadiusTokens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp3) {
            HStack(alignment: .bottom, spacing: NRSpace.sp4) {
                radiusCell("r1", NRRadius.r1)
                radiusCell("r2", NRRadius.r2)
                radiusCell("r3", NRRadius.r3)
                radiusCell("rJar", NRRadius.rJar)
                KitCell("superellipseN = \(Int(NRRadius.superellipseN))") {
                    Superellipse()
                        .fill(NRColor.surface2)
                        .overlay(Superellipse().strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                        .frame(width: 56, height: 56)
                }
            }
            ForEach(NRTokenCatalog.radius, id: \.css) { entry in
                Text("NRRadius.\(entry.swift) = \(entry.value)  (\(entry.css))")
                    .font(NRType.font(NRType.fsXs, design: NRType.fontMono)).foregroundStyle(NRColor.fg2)
            }
        }
    }

    private func radiusCell(_ name: String, _ r: CGFloat) -> some View {
        KitCell("NRRadius.\(name) · \(Int(r))pt") {
            RoundedRectangle(cornerRadius: r)
                .fill(NRColor.surface2)
                .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                .frame(width: 56, height: 56)
        }
    }
}

// MARK: - Type

struct TypeTokens: View {
    private let sizes: [(String, CGFloat)] = [
        ("fsXs", NRType.fsXs), ("fsSm", NRType.fsSm), ("fsMd", NRType.fsMd), ("fsLg", NRType.fsLg),
        ("fsXl", NRType.fsXl), ("fs2xl", NRType.fs2xl), ("fs3xl", NRType.fs3xl),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp3) {
            ForEach(sizes, id: \.0) { name, size in
                HStack(alignment: .firstTextBaseline, spacing: NRSpace.sp4) {
                    Text("NRType.\(name) · \(Int(size))pt")
                        .font(NRType.font(NRType.fsXs, design: NRType.fontMono)).foregroundStyle(NRColor.fg2)
                        .frame(width: 150, alignment: .leading)
                    Text("The browser that preserves your work").font(NRType.font(size, weight: .regular)).foregroundStyle(NRColor.fg)
                    Text("500").font(NRType.font(size, weight: .medium)).foregroundStyle(NRColor.fg2)
                    Text("600").font(NRType.font(size, weight: .semibold)).foregroundStyle(NRColor.fg2)
                }
            }
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline).padding(.vertical, NRSpace.sp1)
            HStack(alignment: .top, spacing: NRSpace.sp8) {
                lineHeight("lhTight", NRType.lhTight)
                lineHeight("lhUI", NRType.lhUI)
                lineHeight("lhBody", NRType.lhBody)
                KitCell("NRType.fontMono · 412 preserved, 0 lost") {
                    Text("https://netrelish.com/pantry · 412 preserved").font(NRType.font(NRType.fsSm, design: NRType.fontMono)).monospacedDigit().foregroundStyle(NRColor.fg)
                }
            }
            Text("NRType.fontHero = \"\(NRType.fontHero)\" — site hero only, never in the app.")
                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
        }
    }

    private func lineHeight(_ name: String, _ lh: CGFloat) -> some View {
        KitCell("NRType.\(name) · \(String(format: "%.2f", lh))") {
            Text("Nothing you read is lost.\nEverything is findable.")
                .font(NRType.font(NRType.fsMd))
                .lineSpacing(NRType.fsMd * (lh - 1))
                .foregroundStyle(NRColor.fg)
                .frame(width: 180, alignment: .leading)
        }
    }
}

// MARK: - Motion

struct MotionTokens: View {
    @Environment(\.nrReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp3) {
            HStack(spacing: NRSpace.sp8) {
                CurveDemo(name: "easeOut", curve: NRMotion.easeOut, duration: NRMotion.base, reduceMotion: reduceMotion)
                CurveDemo(name: "easeJar", curve: NRMotion.easeJar, duration: NRMotion.seal, reduceMotion: reduceMotion)
            }
            ForEach(NRTokenCatalog.motion, id: \.css) { entry in
                Text("NRMotion.\(entry.swift) = \(entry.value)  (\(entry.css))")
                    .font(NRType.font(NRType.fsXs, design: NRType.fontMono)).foregroundStyle(NRColor.fg2)
            }
            if reduceMotion {
                Text("Reduce Motion is on: curves run as fades.").font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
            }
        }
    }
}

struct CurveDemo: View {
    let name: String
    let curve: UnitCurve
    let duration: TimeInterval
    let reduceMotion: Bool
    @State private var atEnd = false

    var body: some View {
        KitCell("NRMotion.\(name) · \(Int(duration * 1000))ms — click to run") {
            ZStack(alignment: .leading) {
                Rectangle().fill(NRColor.hairline).frame(width: 200, height: NRSpace.hairline)
                Circle()
                    .fill(NRColor.fg)
                    .frame(width: 12, height: 12)
                    .offset(x: reduceMotion ? (atEnd ? 188 : 0) : (atEnd ? 188 : 0))
                    .opacity(reduceMotion ? (atEnd ? 0.3 : 1) : 1)
            }
            .frame(width: 200, height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                if reduceMotion {
                    withAnimation(.linear(duration: 0)) { atEnd.toggle() }
                } else {
                    withAnimation(NRMotion.animation(curve, duration: duration)) { atEnd.toggle() }
                }
            }
        }
    }
}
#endif
