// DesignKitSnapshot.swift — DEBUG-only. `NetRelish --snapshot <dir>` renders the
// Design Kit content, light and dark, to PNG and exits. Used for PR demos and CI.

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum DesignKitSnapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        render(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApplication.shared.appearance = NSAppearance(named: appearance)
            let view = DesignKitContent()
                .padding(NRSpace.sp6)
                .frame(width: 1180)
                .background(NRColor.bg)
                .environment(\.colorScheme, name == "dark" ? .dark : .light)
                .environment(\.nrReduceMotion, false)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write("snapshot: failed to render \(name)\n".data(using: .utf8)!)
                exit(1)
            }
            let url = dir.appendingPathComponent("design-kit-\(name).png")
            do { try png.write(to: url) } catch {
                FileHandle.standardError.write("snapshot: \(error)\n".data(using: .utf8)!)
                exit(1)
            }
            print("wrote \(url.path) (\(Int(image.size.width))×\(Int(image.size.height)))")
        }
    }
}
#endif
