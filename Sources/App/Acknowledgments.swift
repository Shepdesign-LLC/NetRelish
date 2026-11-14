// Acknowledgments.swift — Help › Acknowledgments: the third-party notices, as the app ships
// them (non-negotiable 8). The NOTICE text on the neutral surface, in system type, selectable,
// and nothing else: no relish, no links, nothing loaded.

import SwiftUI

enum Acknowledgments {
    /// The window's scene id.
    static let windowId = "acknowledgments"

    /// The notices in the bundle: Contents/Resources/Zest/NOTICE, which `zest/build.sh --app`
    /// copies from the root NOTICE (`vendor.mjs --check` holds the two byte for byte). It lists
    /// everything third-party the app carries, not only what the Zest tools use.
    static var file: URL? {
        ZestFiles.bundledRoot?.appending(path: "NOTICE", directoryHint: .notDirectory)
    }

    /// The notices' text, or nil if the file isn't there or isn't UTF-8.
    static func text(at url: URL? = Acknowledgments.file) -> String? {
        guard let url, let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)),
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }
}

/// The window: the whole NOTICE, top to bottom.
struct AcknowledgmentsView: View {
    private let notice = Acknowledgments.text()

    var body: some View {
        if let notice {
            ScrollView {
                Text(verbatim: notice)
                    .font(NRType.font(NRType.fsSm))
                    .foregroundStyle(NRColor.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(NRSpace.sp6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 480, minHeight: 360)
            .background(NRColor.bg)
        } else {
            EmptyBench(message: "The notices aren’t in this build.")
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}

/// Help › Acknowledgments. A view, so it can reach `openWindow` from the menu bar.
struct AcknowledgmentsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Acknowledgments") { openWindow(id: Acknowledgments.windowId) }
    }
}
