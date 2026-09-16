// Components.swift — the smallest reusable pieces of manifest §8: button styles,
// the badge, the shelf-life bar, the tab lip, and the jar glyph. Hand-written.
// Anything larger (Shelf, Tabs, Bench, Inspector) is P1 feature work.

import SwiftUI

// MARK: - Buttons (§8: Primary / Secondary)

/// Relish fill, `relishInk` text, `r1`, 600 weight. One per view. Hover `relish300`.
/// This is relish placement #1 (manifest §4).
public struct NRPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(NRType.font(NRType.fsMd, weight: .semibold))
                .foregroundStyle(NRColor.relishInk)
                .padding(.horizontal, NRSpace.sp3)
                .padding(.vertical, NRSpace.sp2)
                .background(hovering && isEnabled ? NRColor.relish300 : NRColor.relish500,
                            in: RoundedRectangle(cornerRadius: NRRadius.r1))
                .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.4))
                .onHover { hovering = $0 }
                .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        }
    }
}

/// Hairline border, `fg` text, no fill.
public struct NRSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }

    private struct SecondaryBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(NRType.font(NRType.fsMd, weight: .medium))
                .foregroundStyle(NRColor.fg)
                .padding(.horizontal, NRSpace.sp3)
                .padding(.vertical, NRSpace.sp2)
                .background(hovering && isEnabled ? NRColor.surface2 : .clear,
                            in: RoundedRectangle(cornerRadius: NRRadius.r1))
                .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.4))
                .onHover { hovering = $0 }
                .animation(NRMotion.animation(duration: NRMotion.fast), value: hovering)
        }
    }
}

public extension ButtonStyle where Self == NRPrimaryButtonStyle {
    static var nrPrimary: NRPrimaryButtonStyle { NRPrimaryButtonStyle() }
}
public extension ButtonStyle where Self == NRSecondaryButtonStyle {
    static var nrSecondary: NRSecondaryButtonStyle { NRSecondaryButtonStyle() }
}

// MARK: - Badge (§8; relish placement #6)

/// `relish100` background, `relish700` text, `r1`, tabular numerals. "412 preserved".
public struct NRBadge: View {
    public var text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(NRType.font(NRType.fsXs, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(NRColor.relish700)
            .padding(.horizontal, NRSpace.sp2)
            .padding(.vertical, 2)
            .background(NRColor.relish100, in: RoundedRectangle(cornerRadius: NRRadius.r1))
    }
}

// MARK: - Shelf-life bar (§8; relish placement #5)

/// 2pt bar. `relish500` for remaining life, `warn` under 20%, `hairline` track.
public struct NRShelfLifeBar: View {
    /// Remaining life, 0…1.
    public var remaining: Double
    public init(remaining: Double) { self.remaining = max(0, min(1, remaining)) }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(NRColor.hairline)
                Rectangle()
                    .fill(remaining < 0.2 ? NRColor.warn : NRColor.relish500)
                    .frame(width: geo.size.width * remaining)
            }
        }
        .frame(height: 2)
        .accessibilityLabel("Shelf life")
        .accessibilityValue("\(Int(remaining * 100)) percent remaining")
    }
}

// MARK: - Tab lip (§8; relish placement #2)

/// The `lipH`-tall relish bar on the top edge of the active tab — and only there.
public struct NRTabLip: View {
    public init() {}
    public var body: some View {
        RoundedRectangle(cornerRadius: NRSpace.lipH / 2)
            .fill(NRColor.relish500)
            .frame(height: NRSpace.lipH)
    }
}

// MARK: - Jar glyph

/// `#nr-jar` drawn from shapes at any size: lid, superellipse shoulders, filled body.
/// Prefer `NRSymbol.jar.image` at 24pt; use this when a jar must scale or animate.
public struct NRJarGlyph: View {
    public enum Variant { case plain, smart, pickle }
    public var variant: Variant
    public var size: CGFloat

    public init(_ variant: Variant = .plain, size: CGFloat = 24) {
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        let u = size / 24                  // symbol units → points
        ZStack(alignment: .top) {
            // Lid: stroked rect 9×3 at (7.5, 2.5), rx 1
            RoundedRectangle(cornerRadius: 1 * u)
                .strokeBorder(.primary, lineWidth: max(1, u))
                .frame(width: 9 * u, height: 3 * u)
                .offset(y: 2.5 * u)
            // Body: 11 wide from y=5.5 to 21.5 (16 tall) — shoulders included in JarShape.
            JarShape()
                .fill(.primary)
                .frame(width: 11 * u, height: 16 * u)
                .offset(y: 5.5 * u)
            // Variant glyph, cut out of the body.
            if variant != .plain {
                Image(systemName: variant == .smart ? "line.3.horizontal.decrease" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 6 * u, weight: .semibold))
                    .foregroundStyle(NRColor.surface)
                    .offset(y: 13 * u)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Jar")
    }
}
