// Components.swift — the smallest reusable pieces of manifest §8: button styles,
// the badge, the shelf-life bar, the tab lip and tab shape, the drop mark, and the jar glyph.
// Hand-written.
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
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var hovering = false

        /// The hairline all but disappears on white; under Increase Contrast the edge is `fg3`.
        private var edge: Color { contrast == .increased ? NRColor.fg3 : NRColor.hairline }

        var body: some View {
            configuration.label
                .font(NRType.font(NRType.fsMd, weight: .medium))
                .foregroundStyle(NRColor.fg)
                .padding(.horizontal, NRSpace.sp3)
                .padding(.vertical, NRSpace.sp2)
                .background(hovering && isEnabled ? NRColor.surface2 : .clear,
                            in: RoundedRectangle(cornerRadius: NRRadius.r1))
                .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(edge, lineWidth: NRSpace.hairline))
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

// MARK: - Focus ring (§4 placement 7)

/// The keyboard's ring (manifest v2.1 §4 #7, `--nr-focus`): 2pt, in the shape it marks, just
/// outside it by default, or inside (a positive inset) where a card would clip it. Drawn only,
/// never spoken, and only while the keyboard is there.
struct NRFocusRing: View {
    let cornerRadius: CGFloat
    /// How far in from the edge it marks; negative draws it outside.
    var inset: CGFloat = -2

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(NRColor.focus, lineWidth: 2)
            .padding(inset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// `nrFocusRing`: our ring in place of the system's, which draws in the user's accent color
/// (blue by default), not `--nr-focus`.
private struct NRFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    let inset: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .focused($focused)
            .overlay { if focused { NRFocusRing(cornerRadius: cornerRadius, inset: inset) } }
    }
}

extension View {
    /// For a control that keeps no focus state of its own, such as a `.nrSecondary` or
    /// `.nrPrimary` button (both `r1`): the keyboard's ring in `--nr-focus` (§4 #7).
    func nrFocusRing(cornerRadius: CGFloat = NRRadius.r1, inset: CGFloat = -2) -> some View {
        modifier(NRFocusRingModifier(cornerRadius: cornerRadius, inset: inset))
    }
}

// MARK: - Badge (§8; neutral since v2.1, when §4 #6 narrowed)

/// A count or a short fact: `tab` fill, `fg2` text, `r1`, tabular numerals. "412 preserved".
/// Neutral since manifest v2.1: §4 #6 narrowed to the Ask rank badges and citation markers,
/// so a badge in the chrome never wears relish.
public struct NRBadge: View {
    public var text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(NRType.font(NRType.fsXs, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(NRColor.fg2)
            .padding(.horizontal, NRSpace.sp2)
            .padding(.vertical, 2)
            .background(NRColor.tab, in: RoundedRectangle(cornerRadius: NRRadius.r1))
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
        // One element: the bar's shapes say nothing on their own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shelf life")
        .accessibilityValue(Self.accessibilityValue(remaining: remaining))
    }

    /// "80 percent left", or "15 percent left, running low" under 20%, which the bar shows
    /// only in the warn color.
    static func accessibilityValue(remaining: Double) -> String {
        let left = max(0, min(1, remaining))
        let percent = Int((left * 100).rounded())
        return left < 0.2 ? "\(percent) percent left, running low" : "\(percent) percent left"
    }
}

// MARK: - Tab lip and tab shape (§8 Tabs; §4 #2 stays retired in v2.1)

/// The `lipH`-tall bar on the top edge of the tab in front, in its jar's color — and only
/// there. It is relish only for a Relish jar (manifest v2.1 jar-color list). The tab strip
/// clips it to the tab's rounded top (`NRTabShape`).
public struct NRTabLip: View {
    public var color: Color
    public init(color: Color = NRColor.relish500) { self.color = color }
    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: NRSpace.lipH)
            .accessibilityHidden(true)
    }
}

/// A tab's outline: the top corners rounded, the bottom square, so the tab in front joins
/// the row under it with no seam.
public struct NRTabShape: Shape {
    public var radius: CGFloat
    public init(radius: CGFloat = 8) { self.radius = radius }

    public func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius).path(in: rect)
    }
}

// MARK: - Drop mark (§8; relish placement #9)

/// The `lipH`-wide relish bar on the leading edge of whatever a drag would land on — a jar
/// on the Shelf, a tab in the strip — and only while something is being dragged over it.
public struct NRDropMark: View {
    public init() {}
    public var body: some View {
        RoundedRectangle(cornerRadius: NRSpace.lipH / 2)
            .fill(NRColor.relish500)
            .frame(width: NRSpace.lipH)
            .accessibilityHidden(true)
    }
}

// MARK: - Jar glyph

/// `#nr-jar` drawn from shapes at any size: lid, superellipse shoulders, filled body.
/// Prefer `NRSymbol.jar.image` at 24pt; use this when a jar must scale or animate.
public struct NRJarGlyph: View {
    public enum Variant { case plain, smart, mason }
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
        // One element, so the variant's inner symbol never takes the name. Beside a jar's
        // own name, hide the glyph at the call site instead, as NRFilledJar is.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenName(of: variant))
    }

    /// What VoiceOver calls the glyph: "Jar", "Smart jar" or "Mason Jar".
    static func spokenName(of variant: Variant) -> String {
        switch variant {
        case .plain: return "Jar"
        case .smart: return "Smart jar"
        case .mason: return "Mason Jar"
        }
    }
}
