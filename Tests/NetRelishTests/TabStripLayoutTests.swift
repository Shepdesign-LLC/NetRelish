import Foundation
import Testing
@testable import NetRelish

/// How wide the tabs in the title strip are (the facelift comp's `tabLayout`): every tab
/// shares the room between `tabMinW` and `tabMaxW`, the tab in front grows to fit its title up
/// to `frontTabMaxW` before the others shrink, and a pinned tab is always `pinnedTabW`.
@Suite("Tab strip layout") struct TabStripLayoutTests {

    /// The strip's width in the comp's 1238pt window: everything right of the Shelf.
    private let roomy: CGFloat = 1118

    @Test("With plenty of room, every tab is as wide as a tab gets")
    func plentyOfRoom() {
        let widths = TabStripLayout.widths(pinned: [false, false, false], frontIndex: 1,
                                           frontIdealWidth: 120, available: roomy)
        #expect(widths == [NRShell.tabMaxW, NRShell.tabMaxW, NRShell.tabMaxW])
    }

    @Test("A crowded strip holds every tab at the narrowest a tab gets")
    func crowded() {
        let pinned = Array(repeating: false, count: 12)
        let widths = TabStripLayout.widths(pinned: pinned, frontIndex: 0,
                                           frontIdealWidth: nil, available: roomy)
        #expect(widths.count == 12)
        #expect(widths.allSatisfy { $0 == NRShell.tabMinW })
    }

    @Test("Between the bounds, the tabs share the room exactly")
    func sharesTheRoom() {
        // free = 1118 - 44 - 6 * 4 = 1050; 1050 / 6 = 175
        let widths = TabStripLayout.widths(pinned: Array(repeating: false, count: 6), frontIndex: nil,
                                           frontIdealWidth: nil, available: roomy)
        #expect(widths.allSatisfy { $0 == 175 })
    }

    @Test("A long title in front grows its tab, up to its limit, and the others shrink")
    func longFrontTitle() {
        let pinned = Array(repeating: false, count: 6)
        // Fits: the front asks for 240 and gets it; the others share what's left.
        let fits = TabStripLayout.widths(pinned: pinned, frontIndex: 2, frontIdealWidth: 240, available: roomy)
        #expect(fits[2] == 240)
        #expect(fits[0] == 162)   // (1050 - 240) / 5
        #expect(fits[0] < 175)
        // Too long: the front stops at frontTabMaxW.
        let long = TabStripLayout.widths(pinned: pinned, frontIndex: 2, frontIdealWidth: 900, available: roomy)
        #expect(long[2] == NRShell.frontTabMaxW)
        #expect(long[0] == 158)   // (1050 - 260) / 5
        #expect(Set(long.enumerated().filter { $0.offset != 2 }.map(\.element)) == [158])
    }

    @Test("A short title in front keeps the shared width")
    func shortFrontTitle() {
        let widths = TabStripLayout.widths(pinned: Array(repeating: false, count: 6), frontIndex: 0,
                                           frontIdealWidth: 100, available: roomy)
        #expect(widths.allSatisfy { $0 == 175 })
    }

    @Test("Pinned tabs are always pinnedTabW, in front or not")
    func pinned() {
        let widths = TabStripLayout.widths(pinned: [true, true, false, false], frontIndex: 0,
                                           frontIdealWidth: 900, available: roomy)
        #expect(widths[0] == NRShell.pinnedTabW)
        #expect(widths[1] == NRShell.pinnedTabW)
        // A pinned tab in front never grows, so the unpinned tabs keep the shared width.
        #expect(widths[2] == NRShell.tabMaxW)
        #expect(widths[3] == NRShell.tabMaxW)
    }

    @Test("A lone front tab grows to fit even when it is the only unpinned tab")
    func loneFront() {
        let widths = TabStripLayout.widths(pinned: [false], frontIndex: 0, frontIdealWidth: 250, available: 600)
        #expect(widths == [250])
    }

    @Test("No tabs, no widths")
    func empty() {
        #expect(TabStripLayout.widths(pinned: [], frontIndex: nil, frontIdealWidth: nil, available: roomy).isEmpty)
    }
}
