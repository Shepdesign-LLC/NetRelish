// SealAnchors.swift — where the window's Seal overlay reads its positions from (ADR 0035).
// The strip, each tab, "+", the address row's Seal slot, the page and every jar on the Shelf
// publish their bounds into one preference; ContentView applies `.sealOverlay(_:)` once, and
// the overlay resolves them against the whole window. Hand-written.

import SwiftUI

/// A place the Seal motion starts from, passes or lands on.
enum SealAnchorRole: Hashable {
    case tabStrip
    case tab(String)
    case newTab
    case sealSlot
    case page
    case jar(String)
}

struct SealAnchorKey: PreferenceKey {
    typealias Value = [SealAnchorRole: Anchor<CGRect>]
    /// Computed, so Swift 6 never asks `Anchor` to be Sendable for a stored static.
    static var defaultValue: Value { [:] }
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's bounds for the Seal overlay under `role`.
    func sealAnchor(_ role: SealAnchorRole) -> some View {
        anchorPreference(key: SealAnchorKey.self, value: .bounds) { [role: $0] }
    }

    /// The window's one Seal overlay, over everything this view holds. It never takes a click
    /// and is hidden from VoiceOver: the field's status line says what Seal did.
    func sealOverlay(_ workbench: Workbench) -> some View {
        overlayPreferenceValue(SealAnchorKey.self) { anchors in
            GeometryReader { proxy in
                SealOverlay(workbench: workbench,
                            rects: anchors.mapValues { proxy[$0] },
                            size: proxy.size)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
