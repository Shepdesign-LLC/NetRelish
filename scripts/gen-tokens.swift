#!/usr/bin/env swift
// gen-tokens.swift — reads design/tokens.css, writes Sources/UI/Tokens.swift to stdout.
//
//   swift scripts/gen-tokens.swift design/tokens.css > Sources/UI/Tokens.swift
//
// Rules this script enforces (it exits 1 rather than guess):
//   • every custom property maps to exactly one static, in exactly one enum
//   • the two dark blocks in tokens.css (`@media` and `[data-theme="dark"]`) agree
//   • a dark value must override a light value that exists
//   • no token is invented here — if it isn't in the CSS, it isn't emitted
//
// Colors: OKLCH → OKLab → linear sRGB → XYZ (D65) → linear Display P3 → P3 gamma.
// The sRGB hex in each doc comment is computed the same way and clipped; it is
// compared against the CSS comment's hex fallback and a mismatch is a warning.

import Foundation

// MARK: - CLI

let args = CommandLine.arguments.dropFirst()
guard let cssPath = args.first else {
    FileHandle.standardError.write("usage: gen-tokens.swift <tokens.css>\n".data(using: .utf8)!)
    exit(2)
}
guard let css = try? String(contentsOfFile: cssPath, encoding: .utf8) else {
    fail("cannot read \(cssPath)")
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("gen-tokens: error: \(msg)\n".data(using: .utf8)!)
    exit(1)
}
func warn(_ msg: String) {
    FileHandle.standardError.write("gen-tokens: warning: \(msg)\n".data(using: .utf8)!)
}

// MARK: - CSS parsing

struct Decl {
    let name: String      // --nr-bg
    let value: String     // oklch(99.2% 0.002 100)
    let comment: String?  // "#FCFCFB  window"
}

/// Extracts the body of the first `{ … }` that follows `marker`, honouring nesting.
func block(after marker: String, in text: String) -> String? {
    guard let r = text.range(of: marker) else { return nil }
    var depth = 0, started = false, body = ""
    for ch in text[r.lowerBound...] {
        if ch == "{" { depth += 1; started = true; if depth == 1 { continue } }
        if ch == "}" { depth -= 1; if depth == 0 && started { break } }
        if started { body.append(ch) }
    }
    return body
}

/// Parses `--name: value;` declarations. Several may share a line; a trailing
/// `/* … */` on a line becomes the doc comment of the *last* declaration on it,
/// unless the line holds several, in which case it is dropped (ambiguous).
func parseDecls(_ body: String) -> [Decl] {
    var decls: [Decl] = []
    for rawLine in body.split(separator: "\n", omittingEmptySubsequences: true) {
        var line = String(rawLine)
        var comment: String? = nil
        if let c = line.range(of: "/*") {
            let rest = line[c.upperBound...]
            if let end = rest.range(of: "*/") {
                comment = rest[..<end.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            line = String(line[..<c.lowerBound])
        }
        let parts = line.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, part) in parts.enumerated() {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let name = part[..<colon].trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix("--") else { continue }
            let value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let own = (parts.count == 1 && i == 0) ? comment : nil
            decls.append(Decl(name: name, value: value, comment: own))
        }
    }
    return decls
}

// Strip block comments that sit on their own (section headers) so they can't be
// mistaken for a declaration's trailing comment. Inline trailing ones survive
// because parseDecls handles them per line.
let stripped = css.replacingOccurrences(of: #"^\s*/\*[^\n]*\*/\s*$"#, with: "", options: .regularExpression)

guard let lightBody = block(after: ":root {", in: stripped) else { fail("no `:root {` block") }
let light = parseDecls(lightBody)
let darkA = block(after: "@media (prefers-color-scheme: dark)", in: stripped).map { block(after: ":root", in: $0) ?? "" }.map(parseDecls) ?? []
let darkB = block(after: ":root[data-theme=\"dark\"]", in: stripped).map(parseDecls) ?? []

// Dark blocks must agree exactly (names and values) — otherwise "dark" is ambiguous.
func normalized(_ v: String) -> String { v.split(separator: " ").joined(separator: " ") }
let mapA = Dictionary(uniqueKeysWithValues: darkA.map { ($0.name, normalized($0.value)) })
let mapB = Dictionary(uniqueKeysWithValues: darkB.map { ($0.name, normalized($0.value)) })
if mapA != mapB {
    let names = Set(mapA.keys).union(mapB.keys).filter { mapA[$0] != mapB[$0] }.sorted()
    fail("dark blocks disagree on \(names.joined(separator: ", ")) — the @media block and [data-theme=\"dark\"] must be identical")
}
let dark = mapA

let lightNames = Set(light.map(\.name))
if light.count != lightNames.count { fail("a property is declared twice in :root") }
for name in dark.keys where !lightNames.contains(name) {
    fail("\(name) has a dark value but no light value")
}

// MARK: - Naming

/// `--nr-fg-2` → `fg2`, `--relish-500` → `relish500`, `--fs-2xl` → `fs2xl`, `--t-seal` → `seal`.
func swiftName(_ css: String, dropping prefixes: [String]) -> String {
    var s = String(css.dropFirst(2))
    for p in prefixes where s.hasPrefix(p + "-") { s = String(s.dropFirst(p.count + 1)); break }
    let parts = s.split(separator: "-").map(String.init)
    guard let first = parts.first else { return s }
    return first + parts.dropFirst().map { p in
        // Numeric chunks stay glued: fg-2 → fg2, fs-2xl → fs2xl. Acronyms stay upper: font-ui → fontUI.
        if p.first!.isNumber { return p }
        if acronyms.contains(p) { return p.uppercased() }
        return p.prefix(1).uppercased() + p.dropFirst()
    }.joined()
}
let acronyms: Set<String> = ["ui"]

/// Escapes a value for use inside a Swift string literal.
func lit(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - Color maths

struct RGB { var r: Double, g: Double, b: Double }

func oklchToLinearSRGB(L: Double, C: Double, H: Double) -> RGB {
    let h = H * .pi / 180
    let a = C * cos(h), b = C * sin(h)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b
    let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
    return RGB(
        r: 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
}

func linearSRGBToLinearP3(_ c: RGB) -> RGB {
    // sRGB → XYZ (D65)
    let X = 0.4123907993 * c.r + 0.3575843394 * c.g + 0.1804807884 * c.b
    let Y = 0.2126390059 * c.r + 0.7151686788 * c.g + 0.0721923154 * c.b
    let Z = 0.0193308187 * c.r + 0.1191947798 * c.g + 0.9505321522 * c.b
    // XYZ → Display P3 (D65)
    return RGB(
        r: 2.4934969119 * X - 0.9313836179 * Y - 0.4027107845 * Z,
        g: -0.8294889696 * X + 1.7626640603 * Y + 0.0236246858 * Z,
        b: 0.0358458302 * X - 0.0761723893 * Y + 0.9568845240 * Z)
}

func gamma(_ v: Double) -> Double {   // sRGB / P3 transfer function
    v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
}
func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

struct ParsedColor {
    let p3: RGB          // gamma-encoded Display P3, clamped
    let srgbHex: String  // clipped sRGB render, for the doc comment
    let clippedP3: Bool
}

func parseOKLCH(_ value: String) -> ParsedColor? {
    // oklch(99.2% 0.002 100)  |  oklch(100% 0 0)
    guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), value.hasPrefix("oklch") else { return nil }
    let comps = value[value.index(after: open)..<close].split(separator: " ").map(String.init)
    guard comps.count == 3 else { return nil }
    func num(_ s: String) -> Double? {
        s.hasSuffix("%") ? Double(s.dropLast()).map { $0 / 100 } : Double(s)
    }
    guard let L = num(comps[0]), let C = Double(comps[1]), let H = Double(comps[2]) else { return nil }
    let lin = oklchToLinearSRGB(L: L, C: C, H: H)
    let p3lin = linearSRGBToLinearP3(lin)
    let clipped = [p3lin.r, p3lin.g, p3lin.b].contains { $0 < -0.0005 || $0 > 1.0005 }
    let p3 = RGB(r: gamma(clamp01(p3lin.r)), g: gamma(clamp01(p3lin.g)), b: gamma(clamp01(p3lin.b)))
    let s = [lin.r, lin.g, lin.b].map { Int((gamma(clamp01($0)) * 255).rounded()) }
    let hex = String(format: "#%02X%02X%02X", s[0], s[1], s[2])
    return ParsedColor(p3: p3, srgbHex: hex, clippedP3: clipped)
}

func hexIn(_ comment: String?) -> String? {
    guard let c = comment, let r = c.range(of: #"#[0-9A-Fa-f]{6}"#, options: .regularExpression) else { return nil }
    return String(c[r]).uppercased()
}
func hexDistance(_ a: String, _ b: String) -> Int {
    func comps(_ h: String) -> [Int] { let v = Int(h.dropFirst(), radix: 16)!; return [(v >> 16) & 255, (v >> 8) & 255, v & 255] }
    return zip(comps(a), comps(b)).map { abs($0 - $1) }.max() ?? 0
}

func fmt(_ v: Double) -> String { String(format: "%.4f", v) }

// MARK: - Classification

enum Home { case color, space, radius, type, motion }

func home(of name: String) -> Home? {
    let n = String(name.dropFirst(2))
    if n.hasPrefix("relish-") || ["nr-bg", "nr-surface", "nr-surface-2", "nr-hairline", "nr-fg", "nr-fg-2", "nr-fg-3",
                                    "nr-squircle", "nr-steel", "nr-danger", "nr-warn", "nr-focus"].contains(n) { return .color }
    if n.hasPrefix("sp-") || ["shelf-w", "inspector-w", "tab-h", "lip-h", "hairline"].contains(n) { return .space }
    if n.hasPrefix("r-") || n == "superellipse-n" { return .radius }
    if n.hasPrefix("font-") || n.hasPrefix("fs-") || n.hasPrefix("lh-") { return .type }
    if n.hasPrefix("ease-") || n.hasPrefix("t-") { return .motion }
    return nil
}

for d in light where home(of: d.name) == nil {
    fail("\(d.name) has no enum to live in (NRColor / NRSpace / NRRadius / NRType / NRMotion) — add a rule here or remove the token")
}

// MARK: - Emission

var out = ""
func line(_ s: String = "") { out += s + "\n" }

let scriptName = "scripts/gen-tokens.swift"
line("// GENERATED by \(scriptName) from design/tokens.css — DO NOT EDIT.")
line("// Regenerate:  swift \(scriptName) design/tokens.css > Sources/UI/Tokens.swift")
line("// CI fails if this file differs from a fresh run. Change tokens.css, not this file.")
line()
line("import AppKit")
line("import SwiftUI")
line()

struct Emitted { let css: String; let swift: String; let enumName: String; let describe: String }
var catalog: [Emitted] = []

func doc(_ d: Decl, extra: String? = nil) -> String {
    var s = "    /// `\(d.name)`"
    if let c = d.comment, !c.isEmpty { s += " — \(c.replacingOccurrences(of: "  ", with: " "))" }
    if let e = extra { s += " · \(e)" }
    return s
}

// --- NRColor -------------------------------------------------------------
line("/// Colors from tokens.css. Display P3, light + dark via a dynamic `NSColor`.")
line("/// `--nr-squircle` and `--nr-steel` exist only so the mark renders from tokens (manifest §2).")
line("public enum NRColor {")
var aliasQueue: [(Decl, String)] = []
for d in light where home(of: d.name) == .color {
    let name = swiftName(d.name, dropping: ["nr"])
    if d.value.hasPrefix("var(") {
        let target = d.value.dropFirst(4).dropLast().trimmingCharacters(in: .whitespaces)
        guard home(of: target) == .color else { fail("\(d.name) aliases \(target), which is not a color") }
        if let dv = dark[d.name], dv != normalized(d.value) { fail("\(d.name) is an alias in light but a value in dark") }
        aliasQueue.append((d, swiftName(target, dropping: ["nr"])))
        catalog.append(Emitted(css: d.name, swift: name, enumName: "NRColor", describe: "= \(target)"))
        continue
    }
    guard let lp = parseOKLCH(d.value) else { fail("\(d.name): cannot parse color `\(d.value)`") }
    if let want = hexIn(d.comment), hexDistance(want, lp.srgbHex) > 2 {
        warn("\(d.name) light renders \(lp.srgbHex) in sRGB; tokens.css comment says \(want)")
    }
    if lp.clippedP3 { warn("\(d.name) light is outside Display P3 and was clamped") }
    var dp: ParsedColor? = nil
    if let dv = dark[d.name] {
        guard let parsed = parseOKLCH(dv) else { fail("\(d.name): cannot parse dark color `\(dv)`") }
        dp = parsed
        if parsed.clippedP3 { warn("\(d.name) dark is outside Display P3 and was clamped") }
    }
    let extra = dp.map { "light \(lp.srgbHex) · dark \($0.srgbHex)" } ?? "\(lp.srgbHex)"
    line(doc(d, extra: extra))
    if let dp {
        line("    public static let \(name) = Color(nsColor: nr_dynamic(")
        line("        light: (\(fmt(lp.p3.r)), \(fmt(lp.p3.g)), \(fmt(lp.p3.b))),")
        line("        dark: (\(fmt(dp.p3.r)), \(fmt(dp.p3.g)), \(fmt(dp.p3.b)))))")
    } else {
        line("    public static let \(name) = Color(nsColor: nr_p3(\(fmt(lp.p3.r)), \(fmt(lp.p3.g)), \(fmt(lp.p3.b))))")
    }
    catalog.append(Emitted(css: d.name, swift: name, enumName: "NRColor", describe: extra))
}
for (d, target) in aliasQueue {
    line(doc(d, extra: "alias"))
    line("    public static let \(swiftName(d.name, dropping: ["nr"])) = \(target)")
}
line("}")
line()

// --- Scalars ---------------------------------------------------------------
func px(_ v: String, for name: String) -> String {
    guard v.hasSuffix("px"), let n = Double(v.dropLast(2)) else { fail("\(name): expected a px value, got `\(v)`") }
    return n == n.rounded() ? String(Int(n)) : String(n)
}

line("/// Spacing and layout, in points. 4pt grid.")
line("public enum NRSpace {")
for d in light where home(of: d.name) == .space {
    let name = swiftName(d.name, dropping: [])
    line(doc(d))
    line("    public static let \(name): CGFloat = \(px(d.value, for: d.name))")
    catalog.append(Emitted(css: d.name, swift: name, enumName: "NRSpace", describe: d.value))
}
line("}")
line()

line("/// Corner radii, in points, and the superellipse exponent.")
line("public enum NRRadius {")
for d in light where home(of: d.name) == .radius {
    let name = swiftName(d.name, dropping: [])
    line(doc(d))
    if d.name == "--superellipse-n" {
        guard let n = Double(d.value) else { fail("\(d.name): expected a number") }
        line("    public static let \(name): Double = \(n == n.rounded() ? String(Int(n)) : String(n))")
    } else {
        line("    public static let \(name): CGFloat = \(px(d.value, for: d.name))")
    }
    catalog.append(Emitted(css: d.name, swift: name, enumName: "NRRadius", describe: d.value))
}
line("}")
line()

line("/// Type. Sizes in points, line heights as multipliers. Weights 400/500/600 only (manifest §5).")
line("public enum NRType {")
for d in light where home(of: d.name) == .type {
    let name = swiftName(d.name, dropping: [])
    line(doc(d))
    switch d.name {
    case "--font-ui":   line("    public static let \(name): Font.Design = .default")
    case "--font-mono": line("    public static let \(name): Font.Design = .monospaced")
    case "--font-hero":
        // Site only. Emitted so the property has its one static; the app never uses it.
        let family = d.value.split(separator: ",").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) } ?? d.value
        line("    public static let \(name): String = \"\(family)\"")
    default:
        if d.name.hasPrefix("--fs-") {
            line("    public static let \(name): CGFloat = \(px(d.value, for: d.name))")
        } else {
            guard let n = Double(d.value) else { fail("\(d.name): expected a number") }
            line("    public static let \(name): CGFloat = \(n)")
        }
    }
    catalog.append(Emitted(css: d.name, swift: name, enumName: "NRType", describe: d.value))
}
line()
line("    /// System font at a token size. `design` defaults to `fontUI`; pass `fontMono` for code and URLs.")
line("    public static func font(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = fontUI) -> Font {")
line("        .system(size: size, weight: weight, design: design)")
line("    }")
line("}")
line()

line("/// Motion. Durations in seconds, curves as `UnitCurve`. `seal` is the one drip (manifest §9).")
line("public enum NRMotion {")
for d in light where home(of: d.name) == .motion {
    let name = swiftName(d.name, dropping: ["t"])
    line(doc(d))
    if d.name.hasPrefix("--ease-") {
        guard let open = d.value.firstIndex(of: "("), let close = d.value.lastIndex(of: ")") else { fail("\(d.name): expected cubic-bezier(…)") }
        let c = d.value[d.value.index(after: open)..<close].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard c.count == 4 else { fail("\(d.name): expected four bezier control values") }
        line("    public static let \(name) = UnitCurve.bezier(startControlPoint: UnitPoint(x: \(c[0]), y: \(c[1])), endControlPoint: UnitPoint(x: \(c[2]), y: \(c[3])))")
    } else {
        guard d.value.hasSuffix("ms"), let ms = Double(d.value.dropLast(2)) else { fail("\(d.name): expected a ms value") }
        line("    public static let \(name): TimeInterval = \(ms / 1000)")
    }
    catalog.append(Emitted(css: d.name, swift: name, enumName: "NRMotion", describe: d.value))
}
line()
line("    /// An `Animation` from a token curve and a token duration.")
line("    public static func animation(_ curve: UnitCurve = easeOut, duration: TimeInterval = base) -> Animation {")
line("        .timingCurve(curve, duration: duration)")
line("    }")
line("}")
line()

// --- Catalogue (for the Design Kit and the round-trip test) ----------------
line("/// Every token, by CSS name, for the Design Kit and tests. Generated alongside the enums.")
line("public enum NRTokenCatalog {")
line("    public struct ColorEntry: Sendable { public let css: String; public let swift: String; public let color: Color; public let note: String }")
line("    public struct ScalarEntry: Sendable { public let css: String; public let swift: String; public let value: String }")
line()
line("    public static let colors: [ColorEntry] = [")
for e in catalog where e.enumName == "NRColor" {
    line("        ColorEntry(css: \"\(e.css)\", swift: \"\(e.swift)\", color: NRColor.\(e.swift), note: \"\(lit(e.describe))\"),")
}
line("    ]")
for (enumName, listName) in [("NRSpace", "space"), ("NRRadius", "radius"), ("NRType", "typography"), ("NRMotion", "motion")] {
    line("    public static let \(listName): [ScalarEntry] = [")
    for e in catalog where e.enumName == enumName {
        line("        ScalarEntry(css: \"\(e.css)\", swift: \"\(e.swift)\", value: \"\(lit(e.describe))\"),")
    }
    line("    ]")
}
line()
line("    /// Every CSS custom property this file was generated from — one static each.")
line("    public static let allCSSNames: [String] = [")
for e in catalog { line("        \"\(e.css)\",") }
line("    ]")
line("}")
line()

// --- Helpers ---------------------------------------------------------------
line("// MARK: - Helpers (generated once, not tokens)")
line()
line("/// A Display P3 color that is the same in light and dark.")
line("private func nr_p3(_ r: Double, _ g: Double, _ b: Double) -> NSColor {")
line("    NSColor(displayP3Red: r, green: g, blue: b, alpha: 1)")
line("}")
line()
line("/// A Display P3 color that resolves against the drawing appearance: light for Aqua, dark for Dark Aqua.")
line("private func nr_dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> NSColor {")
line("    NSColor(name: nil) { appearance in")
line("        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua")
line("        let c = isDark ? dark : light")
line("        return NSColor(displayP3Red: c.0, green: c.1, blue: c.2, alpha: 1)")
line("    }")
line("}")

FileHandle.standardOutput.write(out.data(using: .utf8)!)
