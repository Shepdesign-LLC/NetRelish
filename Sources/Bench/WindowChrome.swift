// WindowChrome.swift — the small AppKit pieces of the title strip (manifest v2.1 §8, the
// Workbench facelift comp's build notes): the window's close, minimize and zoom buttons moved
// to sit centered in the 44pt strip, and the empty stretches of the strip that move the
// window. A double-click on the title bar stays AppKit's: it reads the user's setting itself,
// so the app never reads it. Hand-written.

import AppKit
import SwiftUI

/// Moves the window's close, minimize and zoom buttons into the title strip: the close button
/// `NRShell.windowButtonsLeading` from the leading edge, the others keeping their spacing, each
/// centered `NRShell.windowButtonsCenterY` from the window's top. AppKit lays the title bar out
/// again on resize, on leaving full screen and on becoming key, so the move is reapplied then.
///
/// This is cosmetic, and it leans on AppKit's private title-bar layout: if a button or the
/// title-bar container is missing, it does nothing and the buttons stay where AppKit put them.
/// In full screen it stands aside.
///
/// Use it as a background of the title strip.
struct WindowButtonsPlacement: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        let coordinator = context.coordinator
        view.onWindow = { [weak coordinator] window in coordinator?.attach(to: window) }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {}

    static func dismantleNSView(_ nsView: WindowProbeView, coordinator: Coordinator) {
        nsView.onWindow = nil
        coordinator.detach()
    }

    @MainActor final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        /// The view moved into `window` (or out of every window, when nil).
        func attach(to window: NSWindow?) {
            guard let window else {
                detach()
                return
            }
            if window === self.window {
                place()
                return
            }
            detach()
            self.window = window
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                }
                observers.append(token)
            }
            place()
            // AppKit may lay the title bar out once more before the window first shows.
            Task { @MainActor [weak self] in self?.place() }
        }

        func detach() {
            for token in observers { NotificationCenter.default.removeObserver(token) }
            observers = []
            window = nil
        }

        private func place() {
            guard let window else { return }
            WindowButtons.place(in: window)
        }
    }
}

/// A view that says when it lands in a window. It never takes a click.
final class WindowProbeView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Where the window's buttons go, and the move itself.
enum WindowButtons {
    @MainActor static func place(in window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let minimize = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let titlebar = close.superview,
              let container = titlebar.superview,
              minimize.superview === titlebar, zoom.superview === titlebar else { return }

        // AppKit's title-bar container keeps its own height: it never grows over the tabs, so
        // a tab's drag, drop, right-click and hover stay the strip's. It only grows, when it
        // has to, by the point or two a button centered lower needs to stay clickable.
        let buttonsH = max(close.frame.height, minimize.frame.height, zoom.frame.height)
        let needed = (NRShell.windowButtonsCenterY + buttonsH / 2).rounded(.up)
        if container.frame.height < needed {
            let windowH = container.superview?.bounds.height ?? window.frame.height
            var frame = container.frame
            frame.size.height = needed
            // The container's superview is not flipped: the origin is the container's bottom edge.
            frame.origin.y = windowH - needed
            container.frame = frame
        }
        // The title-bar view holds the three buttons and nothing else, so it must never be as
        // wide as the window. Stretched across the strip it lies over the mark and every tab,
        // and AppKit's own window-move claims a press-and-drag there before SwiftUI can start
        // a drag session — which is why a tab could not be dragged onto a jar from the facelift
        // (8de5828) until this was fixed. docs/subsystems/workbench-shell.md carries it as a
        // trap, and `container.bounds` walked straight into it. It stops at the mark's leading
        // edge; the buttons end well before that.
        if titlebar.frame.height < container.bounds.height {
            var frame = container.bounds
            frame.size.width = min(frame.size.width, NRShell.markLeading)
            titlebar.frame = frame
        }

        // Keep AppKit's own spacing between the three buttons.
        let toMinimize = minimize.frame.minX - close.frame.minX
        let toZoom = zoom.frame.minX - minimize.frame.minX
        let xs = [NRShell.windowButtonsLeading,
                  NRShell.windowButtonsLeading + toMinimize,
                  NRShell.windowButtonsLeading + toMinimize + toZoom]
        for (button, x) in zip([close, minimize, zoom], xs) {
            let h = button.frame.height
            let fromTop = NRShell.windowButtonsCenterY - h / 2
            let y = titlebar.isFlipped ? fromTop : titlebar.bounds.height - fromTop - h
            let origin = NSPoint(x: x.rounded(), y: y.rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// An empty stretch of the title strip: dragging it moves the window. A double-click on the
/// strip is left to AppKit's title bar, which applies System Settings › Desktop & Dock itself.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .accessibilityHidden(true)
    }
}
