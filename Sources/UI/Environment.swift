// Environment.swift — the one environment value the design system adds.

import SwiftUI

/// Reduce Motion, as the design system sees it. Defaults to the system setting;
/// the Design Kit overrides it so both branches of every animation can be demoed.
/// Manifest §9: under Reduce Motion, Seal becomes a fade.
public extension EnvironmentValues {
    @Entry var nrReduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}
