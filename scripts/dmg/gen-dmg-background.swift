#!/usr/bin/env swift
// gen-dmg-background.swift — draws the window the disk image opens to. The brand's neutral
// base, a hairline footer on the second surface, one line of copy in the system font, and a
// quiet arrow from NetRelish to Applications (manifest §1, §3, §5, §6). No relish: the disk
// image isn't on the §4 list. The mark appears as the app's own icon and the disk's icon,
// never drawn into the background (§2).
//
//   swift scripts/dmg/gen-dmg-background.swift <layout.json> <out-dir>
//       writes background.png and background@2x.png
//   swift scripts/dmg/gen-dmg-background.swift <layout.json> <out-dir> --preview <NetRelish.app>
//       also writes preview.png and preview@2x.png: the background with both icons and their
//       labels where Finder puts them, for a PR to show what the window looks like
//
// Finder draws a window with a background picture in Light Mode whatever the system
// appearance, so the light tokens are the right ones in both.

import AppKit

struct Layout: Decodable {
    let width: Double, height: Double, iconSize: Double, textSize: Double
    let app: [Double], applications: [Double]
    let footerHeight: Double
    let copy: String
}

/// Light values from design/tokens.css (manifest §3).
enum Token {
    static let bg = NSColor(srgbHex: 0xFCFCFB)        // --nr-bg
    static let surface2 = NSColor(srgbHex: 0xF5F5F3)  // --nr-surface-2
    static let hairline = NSColor(srgbHex: 0xE3E3E0)  // --nr-hairline
    static let fg = NSColor(srgbHex: 0x1D1D1B)        // --nr-fg
    static let fg2 = NSColor(srgbHex: 0x66665F)       // --nr-fg-2
    static let fg3 = NSColor(srgbHex: 0x93938B)       // --nr-fg-3
}

extension NSColor {
    convenience init(srgbHex hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("gen-dmg-background: \(message)\n".data(using: .utf8)!)
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 || (args.count == 4 && args[2] == "--preview") else {
    FileHandle.standardError.write("usage: gen-dmg-background.swift <layout.json> <out-dir> [--preview <NetRelish.app>]\n".data(using: .utf8)!)
    exit(2)
}
guard let data = FileManager.default.contents(atPath: args[0]),
      let layout = try? JSONDecoder().decode(Layout.self, from: data) else { fail("cannot read \(args[0])") }
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let previewApp = args.count == 4 ? args[3] : nil

/// Layout points are top-left based, as Finder's are; AppKit draws from the bottom left.
func flip(_ y: Double) -> Double { layout.height - y }

func drawBackground() {
    Token.bg.setFill()
    NSRect(x: 0, y: 0, width: layout.width, height: layout.height).fill()

    // Footer: the second surface under a hairline, the way the Shelf and Panel sit on the window.
    Token.surface2.setFill()
    NSRect(x: 0, y: 0, width: layout.width, height: layout.footerHeight).fill()
    Token.hairline.setFill()
    NSRect(x: 0, y: layout.footerHeight - 1, width: layout.width, height: 1).fill()

    let copy = NSAttributedString(string: layout.copy, attributes: [
        .font: NSFont.systemFont(ofSize: layout.textSize, weight: .regular),
        .foregroundColor: Token.fg2,
    ])
    let size = copy.size()
    copy.draw(at: NSPoint(x: (layout.width - size.width) / 2, y: (layout.footerHeight - size.height) / 2))

    // The arrow: a line with an open head, in the tertiary neutral, between the two icons.
    let y = flip(layout.app[1])
    let gap = 28.0
    let start = layout.app[0] + layout.iconSize / 2 + gap
    let end = layout.applications[0] - layout.iconSize / 2 - gap
    let head = 7.0
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: start, y: y))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.move(to: NSPoint(x: end - head, y: y + head))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.line(to: NSPoint(x: end - head, y: y - head))
    arrow.lineWidth = 1.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    Token.fg3.setStroke()
    arrow.stroke()
}

/// Both icons and their names where Finder will put them: the icon centered on its point,
/// the name under it in the system font at the window's text size, black, as Finder draws it.
func drawIcons(app: String) {
    let items: [(String, String, [Double])] = [
        (app, "NetRelish", layout.app),
        ("/Applications", "Applications", layout.applications),
    ]
    for (path, name, point) in items {
        // A freshly built app isn't registered with Launch Services yet, so ask for its own
        // icon file rather than the generic one Finder would guess.
        let own = (path as NSString).appendingPathComponent("Contents/Resources/AppIcon.icns")
        let icon = NSImage(contentsOfFile: own) ?? NSWorkspace.shared.icon(forFile: path)
        let rect = NSRect(x: point[0] - layout.iconSize / 2, y: flip(point[1]) - layout.iconSize / 2,
                          width: layout.iconSize, height: layout.iconSize)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        let label = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: layout.textSize),
            .foregroundColor: NSColor.black,
        ])
        let size = label.size()
        label.draw(at: NSPoint(x: point[0] - size.width / 2, y: rect.minY - 6 - size.height))
    }
}

func render(_ name: String, scale: Int, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(layout.width) * scale,
                               pixelsHigh: Int(layout.height) * scale, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: layout.width, height: layout.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let file = outDir.appendingPathComponent(scale == 1 ? "\(name).png" : "\(name)@\(scale)x.png")
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode \(file.path)") }
    do { try png.write(to: file) } catch { fail("cannot write \(file.path): \(error)") }
    print("wrote \(file.path)")
}

for scale in [1, 2] {
    render("background", scale: scale, draw: drawBackground)
    if let previewApp {
        render("preview", scale: scale) { drawBackground(); drawIcons(app: previewApp) }
    }
}
