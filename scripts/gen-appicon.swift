#!/usr/bin/env swift
// gen-appicon.swift — renders design/logo.svg to every size macOS wants and packs
// them with iconutil into Resources/AppIcon.icns.
//
//   swift scripts/gen-appicon.swift design/logo.svg Resources/AppIcon.icns
//
// The SVG is rasterised as-is: no redraw, no recolor, no crop (manifest §2).

import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    FileHandle.standardError.write("usage: gen-appicon.swift <logo.svg> <AppIcon.icns>\n".data(using: .utf8)!)
    exit(2)
}
guard let data = FileManager.default.contents(atPath: args[0]), let logo = NSImage(data: data) else {
    FileHandle.standardError.write("gen-appicon: cannot read \(args[0]) as an image\n".data(using: .utf8)!)
    exit(1)
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil's required set: 16, 32, 128, 256, 512, each at 1x and 2x.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: base, height: base)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        logo.draw(in: NSRect(x: 0, y: 0, width: base, height: base), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let out = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { exit(p.terminationStatus) }
print("wrote \(out.path)")
