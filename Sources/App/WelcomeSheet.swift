// WelcomeSheet.swift — the welcome sheet (P5 onboarding, ADR 0038): three cards on what a jar
// is, where idle tabs go, and what Seal does. Shown once, at the first launch, and again from
// Help › Welcome to NetRelish. Start, on the last card, closes it with the caret in the
// address field, so the next thing typed is the first page to seal.
//
// Brand: the cog at 48pt, its onboarding placement (manifest §2), one primary button per card
// (§4 #1), everything else neutral. No new tokens.

import SwiftUI

/// One card of the welcome sheet: a headline and the lines under it.
struct WelcomeCard: Equatable, Sendable {
    let title: String
    let body: String
}

/// Every word of the welcome sheet (docs/voice). The cards say what the app does, in the
/// app's own nouns, and nothing a build doesn't do: tests hold them to that list of rules.
enum WelcomeText {
    static let cards: [WelcomeCard] = [
        WelcomeCard(
            title: "A jar is a project",
            body: "Each jar keeps its own tabs and its own sign-ins, so one client’s accounts stay out of another’s. Add a jar with the + on the Shelf."),
        WelcomeCard(
            title: "Idle tabs sink into Brine",
            body: "Leave a tab alone for its jar’s shelf life and it closes by itself. It waits in Brine, on the bottom bar. Pinned tabs never sink."),
        WelcomeCard(
            title: "Seal a page to keep it",
            body: "Press ⌘S on a page. NetRelish saves a copy of it as it is now, closes the tab and keeps the copy in the jar. Find it again with ⌘K."),
    ]

    static let next = "Next"
    static let back = "Back"
    static let start = "Start"
    /// Help's menu item, which opens the sheet again.
    static let menu = "Welcome to NetRelish"

    /// Where a card is among the cards: "2 of 3".
    static func position(_ index: Int) -> String { "\(index + 1) of \(cards.count)" }

    /// What VoiceOver hears when Next or Back shows another card: nothing moves its cursor
    /// then, so the card is said whole. "Idle tabs sink into Brine. Leave a tab… 2 of 3."
    static func spoken(_ index: Int) -> String {
        let card = cards[index]
        return "\(card.title). \(card.body) \(position(index))."
    }

    /// The card at `index` moved by `step`, held at both ends.
    static func neighbor(of index: Int, by step: Int) -> Int {
        min(max(index + step, 0), cards.count - 1)
    }
}

struct WelcomeSheet: View {
    /// Closes the sheet. True from Start, which also asks for the address field; false from
    /// Escape. Passed in so snapshots can render the view with no Workbench.
    let done: (_ start: Bool) -> Void
    @State private var index: Int

    /// `card` is where the sheet opens: the first card, except in a snapshot of a later one.
    init(card: Int = 0, done: @escaping (_ start: Bool) -> Void) {
        self.done = done
        _index = State(initialValue: WelcomeText.neighbor(of: card, by: 0))
    }

    private var isLast: Bool { index == WelcomeText.cards.count - 1 }

    var body: some View {
        VStack(spacing: NRSpace.sp4) {
            NRLogo.cog.image.resizable().frame(width: 48, height: 48)
                .accessibilityHidden(true)   // the mark, not something to hear
            cards
            Text(WelcomeText.position(index))
                .font(NRType.font(NRType.fsXs)).monospacedDigit().foregroundStyle(NRColor.fg3)
            HStack(spacing: NRSpace.sp3) {
                if index > 0 {
                    Button(WelcomeText.back) { show(-1) }.buttonStyle(.nrSecondary).nrFocusRing()
                }
                // One primary button per view (manifest §4): Next, and Start on the last card.
                Button(isLast ? WelcomeText.start : WelcomeText.next) {
                    if isLast { done(true) } else { show(1) }
                }
                .buttonStyle(.nrPrimary).nrFocusRing().keyboardShortcut(.defaultAction)
            }
        }
        .padding(NRSpace.sp6)
        .frame(width: 420)
        .background(NRColor.surface)
        // No button carries the cancel role, so Escape closes the sheet here.
        .onExitCommand { done(false) }
        // Next and Back change the card under a cursor that stays on the button.
        .onChange(of: index) { _, new in
            NRAnnounce.post(WelcomeText.spoken(new), priority: .high)
        }
    }

    /// Every card, one over the other, with only the one in turn shown. The sheet keeps the
    /// height of its tallest card, so it never resizes under the pointer between cards; the
    /// change is a cross-fade, which is what Reduce Motion asks for too (manifest §9).
    private var cards: some View {
        ZStack {
            ForEach(Array(WelcomeText.cards.enumerated()), id: \.offset) { offset, card in
                VStack(spacing: NRSpace.sp2) {
                    Text(card.title)
                        .font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)
                        .accessibilityAddTraits(.isHeader)
                    Text(card.body)
                        .font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(offset == index ? 1 : 0)
                // A card that isn't showing is not there to read.
                .accessibilityHidden(offset != index)
            }
        }
        .animation(NRMotion.animation(duration: NRMotion.base), value: index)
    }

    private func show(_ step: Int) {
        index = WelcomeText.neighbor(of: index, by: step)
    }
}
