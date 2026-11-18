// WindowChrome.swift — the small AppKit pieces of the title strip (manifest v2.1 §8, the
// Workbench facelift comp's build notes): the window's close, minimize and zoom buttons moved
// to sit centered in the 44pt strip, and the empty stretches of the strip that move the
// window and answer a double-click the way System Settings says. Hand-written.

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
/// Use it as a background of the title strip. `onWindow` hands the strip its window, once the
/// view is in one.
struct WindowButtonsPlacement: NSViewRepresentable {
    var onWindow: ((NSWindow) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        let coordinator = context.coordinator
        coordinator.onWindow = onWindow
        view.onWindow = { [weak coordinator] window in coordinator?.attach(to: window) }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        context.coordinator.onWindow = onWindow
    }

    static func dismantleNSView(_ nsView: WindowProbeView, coordinator: Coordinator) {
        nsView.onWindow = nil
        coordinator.detach()
    }

    @MainActor final class Coordinator {
        var onWindow: ((NSWindow) -> Void)?
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
            onWindow?(window)
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

        let stripH = NRShell.titleH
        let windowH = container.superview?.bounds.height ?? window.frame.height

        // The title-bar container is not flipped: its origin is its bottom edge.
        var frame = container.frame
        frame.size.height = stripH
        frame.origin.y = windowH - stripH
        if container.frame != frame { container.frame = frame }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }

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

/// An empty stretch of the title strip: dragging it moves the window, and a double-click
/// zooms or minimizes it, as System Settings › Desktop & Dock says.
struct WindowDragArea: View {
    let onDoubleClick: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
            .accessibilityHidden(true)
    }

    /// What a double-click on a title bar does, read from the setting macOS keeps for it.
    @MainActor static func titleBarDoubleClick(_ window: NSWindow?) {
        guard let window = window ?? NSApp.keyWindow else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.miniaturize(nil)
        case "None": break
        default: window.zoom(nil)
        }
    }
}

/// The window the title strip is in, held weakly so the strip never keeps it alive. Kept in
/// `@State`, so its window changing never redraws the strip.
final class WeakWindowBox {
    weak var window: NSWindow?
}
