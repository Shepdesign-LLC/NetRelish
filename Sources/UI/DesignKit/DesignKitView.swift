// DesignKitView.swift — DEBUG-only. Window → Design Kit.
// Every token, every symbol, every §8 component state, side by side.

#if DEBUG
import SwiftUI

/// Appearance override for the kit. `.system` follows the Mac.
public enum DesignKitAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

public struct DesignKitView: View {
    @State private var appearance: DesignKitAppearance = .system
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @State private var sealTrigger = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            ScrollView {
                DesignKitContent(sealTrigger: sealTrigger)
                    .padding(NRSpace.sp6)
            }
        }
        .background(NRColor.bg)
        .environment(\.nrReduceMotion, reduceMotion)
        .preferredColorScheme(appearance.colorScheme)
        .frame(minWidth: 960, minHeight: 640)
    }

    private var controls: some View {
        HStack(spacing: NRSpace.sp4) {
            NRLogo.mark.image.resizable().frame(width: 16, height: 16)
            Text("Design Kit").font(NRType.font(NRType.fsMd, weight: .semibold)).foregroundStyle(NRColor.fg)
            Text("Brand Lock v1.1").font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            Spacer()
            Picker("Appearance", selection: $appearance) {
                ForEach(DesignKitAppearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Toggle("Reduce Motion", isOn: $reduceMotion)
                .toggleStyle(.switch)
                .font(NRType.font(NRType.fsSm))
            Button("Seal") { sealTrigger += 1 }
                .buttonStyle(.nrPrimary)
                .keyboardShortcut("s", modifiers: .command)
                .help("Run the Seal animation (⌘S)")
        }
        .padding(.horizontal, NRSpace.sp5)
        .padding(.vertical, NRSpace.sp3)
        .background(NRColor.surface)
    }
}

/// The scrolling body. Split out so the snapshot tool can render it at a fixed size
/// under an explicit color scheme without the controls.
public struct DesignKitContent: View {
    public var sealTrigger: Int
    public init(sealTrigger: Int = 0) { self.sealTrigger = sealTrigger }

    public var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp10) {
            KitSection("Colors", note: "tokens.css → NRColor. Display P3; each swatch resolves for the current appearance.") {
                ColorTokens()
            }
            KitSection("Space · Radius · Layout", note: "NRSpace, NRRadius. 4pt grid.") {
                HStack(alignment: .top, spacing: NRSpace.sp10) {
                    SpaceTokens()
                    RadiusTokens()
                }
            }
            KitSection("Type", note: "NRType. System stack, weights 400/500/600, tabular numerals for counts.") {
                TypeTokens()
            }
            KitSection("Motion", note: "NRMotion. Click a curve to run it. seal is the one drip.") {
                MotionTokens()
            }
            KitSection("Symbols", note: "symbols.svg → NRSymbol, template images. Tint comes from the caller.") {
                SymbolGrid()
            }
            KitSection("The mark", note: "logo.svg and logo-cog.svg → NRLogo. Full color, untouched. Clear space ½ width.") {
                LogoRow()
            }
            KitSection("Shapes", note: "Superellipse(n: 5) and JarShape — sampled from the equation, not border-radius.") {
                ShapeRow()
            }
            KitSection("Components — manifest §8", note: "Every state, side by side. Relish only where §4 allows.") {
                ComponentGallery(sealTrigger: sealTrigger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section chrome

struct KitSection<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, note: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp4) {
            VStack(alignment: .leading, spacing: NRSpace.sp1) {
                Text(title).font(NRType.font(NRType.fsXl, weight: .semibold)).foregroundStyle(NRColor.fg)
                Text(note).font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
            }
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            content()
        }
    }
}

/// A labelled cell in a gallery row.
struct KitCell<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp2) {
            content()
            Text(label).font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
        }
    }
}

#endif
