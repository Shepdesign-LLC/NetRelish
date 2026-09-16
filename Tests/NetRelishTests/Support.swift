import Foundation

/// Repo root, derived from this file's location so tests work from `swift test` and Xcode alike.
let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // NetRelishTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // repo

/// Minimal tokens.css reader for tests: returns (light, dark) maps of `--name` → raw value,
/// plus the hex found in each light/dark line's trailing comment, if any.
struct CSSFixture {
    var light: [String: String] = [:]
    var dark: [String: String] = [:]
    var lightHex: [String: String] = [:]
    var darkHex: [String: String] = [:]

    init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        // Blocks: first `:root {` is light; the `@media` dark block is dark.
        let lightBlock = Self.block(after: ":root {", in: text)
        let darkBlock = Self.block(after: "@media (prefers-color-scheme: dark)", in: text)
        (light, lightHex) = Self.parse(lightBlock)
        (dark, darkHex) = Self.parse(darkBlock)
    }

    private static func block(after marker: String, in text: String) -> String {
        guard let r = text.range(of: marker) else { return "" }
        var depth = 0, started = false
        var out = ""
        for ch in text[r.lowerBound...] {
            if ch == "{" { depth += 1; started = true; if depth == 1 { continue } }
            if ch == "}" { depth -= 1; if depth == 0 && started { break } }
            if started { out.append(ch) }
        }
        return out
    }

    private static func parse(_ block: String) -> ([String: String], [String: String]) {
        var values: [String: String] = [:], hexes: [String: String] = [:]
        for rawLine in block.split(separator: "\n") {
            let line = String(rawLine)
            let hex = line.range(of: #"#[0-9A-Fa-f]{6}"#, options: .regularExpression).map { String(line[$0]) }
            let code = line.range(of: "/*").map { String(line[..<$0.lowerBound]) } ?? line
            for decl in code.split(separator: ";") {
                guard let colon = decl.firstIndex(of: ":") else { continue }
                let name = decl[..<colon].trimmingCharacters(in: .whitespaces)
                guard name.hasPrefix("--") else { continue }
                values[name] = decl[decl.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if let hex { hexes[name] = hex.uppercased() }
            }
        }
        return (values, hexes)
    }
}
