// DesignKitApp.swift — DEBUG-only shell for the Design Kit until the app exists.
// Prompt 2 folds Sources/UI into the app target; the Window scene below moves with it.
//
//   DesignKit                       open the window (Window → Design Kit)
//   DesignKit --snapshot <dir>      render light + dark PNGs into <dir> and exit

import AppKit
import NRUI
import SwiftUI

#if DEBUG
@main
struct DesignKitApp: App {
    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.render(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        // In the real app a `Window` scene gets its Window-menu item for free, because it
        // sits beside the primary WindowGroup. Here it *is* the primary window, so the
        // item is added by hand to keep "Window → Design Kit" true in this shell too.
        Window("Design Kit", id: "design-kit") {
            DesignKitView()
                .onAppear { NSApplication.shared.activate() }
        }
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(after: .windowList) {
                OpenDesignKitCommand()
            }
        }
    }
}

struct OpenDesignKitCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Design Kit") { openWindow(id: "design-kit") }
            .keyboardShortcut("d", modifiers: [.command, .option])
    }
}

/// Renders `DesignKitContent` under an explicit appearance to PNG. Used for the PR demo
/// and by CI, so the kit is proven to render without a screen.
@MainActor
enum Snapshot {
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
#else
@main
struct DesignKitApp {
    static func main() { print("Design Kit is DEBUG-only.") }
}
#endif
