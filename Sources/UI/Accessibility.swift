// Accessibility.swift — what VoiceOver hears that the view tree can't say by itself, and
// the Mac's accessibility display settings handed to the design system (P5).

import AppKit
import SwiftUI

/// Spoken notices for things that happen without focus moving: a Seal landing, a tab
/// sinking to Brine, a jar filling, a Seal that failed. VoiceOver reads them; nothing is
/// drawn, and nothing happens when VoiceOver is off.
@MainActor
public enum NRAnnounce {
    /// Speaks `message`. `.high` interrupts what VoiceOver is saying: use it only for the
    /// result of something the person just did (Seal, a failure). Everything else is
    /// `.medium` and waits its turn.
    public static func post(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard !message.isEmpty, let app = NSApp else { return }
        let target: Any
        if let window = app.keyWindow ?? app.mainWindow { target = window } else { target = app }
        NSAccessibility.post(element: target, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: priority.rawValue])
    }
}

/// Hands the Mac's Reduce Motion setting to the design system, live: SwiftUI's own value
/// changes the moment the setting does, where `nrReduceMotion`'s default is read once.
/// Applied at the root of each window. The Design Kit sets `nrReduceMotion` further in,
/// so its toggle still wins inside the kit.
public struct NRSystemAccessibility: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func body(content: Content) -> some View {
        content.environment(\.nrReduceMotion, reduceMotion)
    }
}

public extension View {
    /// The Mac's accessibility display settings, live, for everything below. Once per window.
    func nrSystemAccessibility() -> some View { modifier(NRSystemAccessibility()) }
}
