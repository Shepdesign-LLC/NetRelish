// ZestWindow.swift — Window › Zest (ADR 0015, ADR 0033). The four free Zest tools, offline,
// in their own window: not tabs, in no jar, never sealed. A plain NetRelish frame (neutral
// surface, a system segmented switcher, no relish) around tools that keep their own look,
// the way the Bench never restyles a page. No keyboard shortcut: ⌘⇧Z is Redo.
//
// Each tool's web view is made the first time it's shown and kept while the window is open,
// so switching never loses what a tool is holding. None is made before the offline rule
// list has compiled.

import AppKit
import SwiftUI
import WebKit

/// The four tools and where each lives under zest://app/. The one table: the switcher, the
/// URLs and the link routing all read it. The folder names are the ones `zest/build.sh --app`
/// writes (ADR 0033): change both together. ZestBundleTests loads each from the bundle.
enum ZestTool: String, CaseIterable, Identifiable {
    case studio, mail, md, image

    var id: String { rawValue }

    private var entry: (title: String, folder: String) {
        switch self {
        case .studio: ("Studio", "")
        case .mail: ("Mail", "mail/")
        case .md: ("MD", "md/")
        case .image: ("Image", "image/")
        }
    }

    /// The switcher's label. Plain text: the fruit icons stay out of NetRelish's chrome.
    var title: String { entry.title }

    /// The folder under zest://app/, with its trailing slash; the studio is the root.
    var folder: String { entry.folder }

    /// The page the tool opens on.
    var url: URL { URL(string: "\(ZestFiles.scheme)://\(ZestFiles.host)/\(folder)index.html")! }

    /// The tool a zest://app/ URL opens: its folder, or the folder's index.html. Nil for any
    /// other file, so a tool's own assets never move the switcher.
    init?(url: URL) {
        guard let components = ZestFiles.components(for: url) else { return nil }
        let path = components.joined(separator: "/")
        guard path == "index.html" || path.hasSuffix("/index.html") else { return nil }
        let folder = String(path.dropLast("index.html".count))
        guard let tool = Self.allCases.first(where: { $0.folder == folder }) else { return nil }
        self = tool
    }
}

/// The Zest window's state: the tool in front and the views made so far.
@MainActor
@Observable
final class ZestWindowModel {
    var tool: ZestTool = .studio
    @ObservationIgnored private var views: [ZestTool: ZestWebView] = [:]
    @ObservationIgnored var openInJar: ((URL) -> Void)?

    /// The tool's view, made on first use and kept from then on.
    func view(for tool: ZestTool, rules: WKContentRuleList, root: URL) -> ZestWebView {
        if let existing = views[tool] { return existing }
        let made = ZestWebView(tool: tool, rules: rules, root: root)
        made.openInJar = { [weak self] url in self?.openInJar?(url) }
        made.showTool = { [weak self] other in self?.tool = other }
        views[tool] = made
        return made
    }

    /// Tools made so far, for tests.
    var madeTools: Set<ZestTool> { Set(views.keys) }

    /// File › Print… for the tool in front, with Save as PDF in the print panel. A tool's own
    /// `window.print()` has nothing to call in the app's web view, so this is how Zest MD's
    /// PDF export happens in the app.
    func printTool(in window: NSWindow?) {
        guard let web = views[tool]?.webView else { return }
        let operation = web.printOperation(with: NSPrintInfo.shared)
        // WebKit lays the page out for paper itself, but its print view comes out blank with no frame.
        operation.view?.frame = web.bounds
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            _ = operation.run()
        }
    }
}

struct ZestWindow: View {
    let workbench: Workbench
    @State private var model = ZestWindowModel()
    @Environment(\.openWindow) private var openWindow
    private var rules: ZestRules { .shared }

    var body: some View {
        content
            .frame(minWidth: 720, minHeight: 480)
            .background(NRColor.bg)
            .navigationTitle("Zest")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Tool", selection: $model.tool) {
                        ForEach(ZestTool.allCases) { tool in Text(tool.title).tag(tool) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Switch tools")
                }
            }
            .background(WindowReader { window in watch(window) })
            .onAppear {
                rules.prepare()
                model.openInJar = { [workbench, openWindow] url in
                    Self.openInActiveJar(url, workbench: workbench, openWindow: openWindow)
                }
                workbench.printZest = { [model, workbench] in model.printTool(in: workbench.zestWindow) }
            }
    }

    @ViewBuilder private var content: some View {
        if let list = rules.list, let root = ZestFiles.bundledRoot {
            ZestPane(web: model.view(for: model.tool, rules: list, root: root).webView)
        } else if rules.failed || (rules.list != nil && ZestFiles.bundledRoot == nil) {
            EmptyBench(message: "Zest couldn’t start. Quit NetRelish and open it again.")
        } else {
            EmptyBench(message: "Opening Zest…")
        }
    }

    /// The window is Zest's: the Workbench is told whenever it is the main window, so Seal,
    /// Capture and Fill from Me stand down while it's in front.
    private func watch(_ window: NSWindow?) {
        workbench.zestWindow = window
        // It may already be main by the time the view lands in it; and a view leaving its
        // window means Zest is no longer in front at all.
        workbench.setZestInFront(window?.isMainWindow == true)
    }

    /// A web link from a tool: an ordinary page load in the active jar, with the main window
    /// brought forward (or opened, if it was closed). The main window is the one `ContentView`
    /// registered, never whichever window comes first: Settings or the Design Kit would
    /// otherwise come forward with the page nowhere on screen.
    private static func openInActiveJar(_ url: URL, workbench: Workbench, openWindow: OpenWindowAction) {
        guard workbench.newTab(url: url.absoluteString) != nil else { return }
        if let main = workbench.mainWindow, main.isVisible || main.isMiniaturized {
            if main.isMiniaturized { main.deminiaturize(nil) }
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: NetRelishApp.mainWindowId)
        }
    }
}

/// Hosts the tool's web view, swapping it in when the switcher moves. The views themselves
/// live in the model, so one taken out of the window keeps its page.
private struct ZestPane: NSViewRepresentable {
    let web: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        place(web, in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if container.subviews.first !== web { place(web, in: container) }
    }

    private func place(_ web: WKWebView, in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        web.frame = container.bounds
        web.autoresizingMask = [.width, .height]
        container.addSubview(web)
    }
}

/// Reports the window a view lands in, so the Zest window and the main window can be told
/// apart from the others.
struct WindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var onWindow: (@MainActor (NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
