import Foundation
import Pantry
import Testing
@testable import NetRelish

/// The facelift's measures (manifest v2.1 §8 and §10, ADR 0035) and the pure parts of the jar
/// drawing and the Seal overlay: the numbers the comp was signed off with, checked where the
/// app keeps them.
@Suite("Shell measures") @MainActor struct ShellMeasureTests {

    @Test("The rows, the tabs and the window minimum are the manifest's")
    func rows() {
        #expect(NRShell.titleH == 44 && NRShell.addressH == 44 && NRShell.fieldH == 28 && NRShell.barH == 32)
        #expect(NRShell.tabH == 33 && NRShell.frontTabH == 38 && NRShell.tabRadius == 8)
        #expect(NRShell.tabMinW == 116 && NRShell.tabMaxW == 224 && NRShell.frontTabMaxW == 260)
        #expect(NRShell.pinnedTabW == 44 && NRShell.tabGap == 4)
        #expect(NRShell.markSize == 28 && NRShell.markLeading == 80)
        #expect(NRShell.windowMinW == 960 && NRShell.windowMinH == 600)
        // The tabs start exactly over the Bench column: the cog sits inside the Shelf's width.
        #expect(NRShell.markLeading + NRShell.markSize <= NRSpace.shelfW)
        // The front tab (6pt down, 38 tall) covers the strip's bottom hairline and stops there.
        #expect(6 + NRShell.frontTabH == NRShell.titleH)
    }

    @Test("A Shelf tile and its slide pitch")
    func tiles() {
        #expect(JarTile.width == 100 && JarTile.height == 88)
        #expect(JarTile.width <= NRSpace.shelfW - 2 * 10)
    }

    @Test("The jar's liquid runs from y 45.5 empty to 15.5 full, in the jar's own units")
    func liquidLevel() {
        #expect(JarLiquidShape.surface(0) == 45.5)
        #expect(JarLiquidShape.surface(1) == 15.5)
        #expect(JarLiquidShape.surface(0.5) == 30.5)
    }

    @Test("A resting jar's fill is held to 0…1; the drip's overshoot only lives in the animation")
    func fillIsClamped() {
        #expect(NRFilledJar(paint: .relish, fill: 1.3).fill == 1)
        #expect(NRFilledJar(paint: .relish, fill: -0.2).fill == 0)
        #expect(NRFilledJar(paint: .relish, fill: 0.5, dropProgress: 2).dropProgress == 1)
        #expect(NRFilledJar(paint: .relish, fill: 0.5).dropProgress == nil)
    }
}

/// The Seal overlay's scene: where the band runs and where drops may hang, worked out from the
/// anchors once when Seal starts (the comp's `sealDrops`).
@Suite("Seal scene") struct SealSceneTests {

    private func run(pinned: Bool = false) -> SealRun {
        SealRun(id: 1, tab: Pantry.Tab(id: "t1", isPinned: pinned, title: "Invoice terms", url: "https://example.com", jarId: "j1"),
                jarId: "j1", index: 0, glyph: nil, startedAt: Date())
    }

    /// One tab in front at x 130, the strip from x 128, "+" after it, in a 1200pt window.
    private var rects: [SealAnchorRole: CGRect] {
        [.tab("t1"): CGRect(x: 130, y: 6, width: 200, height: 38),
         .tabStrip: CGRect(x: 128, y: 0, width: 210, height: 44),
         .newTab: CGRect(x: 340, y: 13, width: 28, height: 28),
         .sealSlot: CGRect(x: 1100, y: 52, width: 28, height: 28)]
    }

    @Test("No front tab in this window: nothing to play")
    func noTabNoScene() {
        var none = rects
        none[.tab("t1")] = nil
        #expect(SealScene.make(run: run(), rects: none, width: 1200, reduceMotion: false) == nil)
    }

    @Test("One tab and an open strip: a nub on the lip and two big drops after +")
    func drops() throws {
        let scene = try #require(SealScene.make(run: run(), rects: rects, width: 1200, reduceMotion: false))
        #expect(scene.bandLeft == 136)
        #expect(scene.bandRight == 1208)
        #expect(scene.lipLeft == 134 && scene.lipRight == 326)
        #expect(scene.drops.count == 3)
        let nub = try #require(scene.drops.first { !$0.big })
        #expect(nub.cx == 130 + 200 * 0.68 && nub.w == 14 && nub.length == 6)
        let big = scene.drops.filter(\.big)
        #expect(big.count == 2)
        // Never over "+" or the tabs: every big drop is past "+" and clear of the window's edge.
        #expect(big.allSatisfy { $0.cx - $0.w / 2 > 368 && $0.cx + $0.w / 2 < 1200 })
        // The stagger runs outward from the tab: the nub first.
        #expect(Set(scene.drops.map(\.order)) == [0, 1, 2])
        #expect(nub.order == 0)
    }

    @Test("A pinned tab's nub is centered and narrower")
    func pinnedNub() throws {
        var pinned = rects
        pinned[.tab("t1")] = CGRect(x: 130, y: 6, width: 44, height: 38)
        let scene = try #require(SealScene.make(run: run(pinned: true), rects: pinned, width: 1200, reduceMotion: false))
        let nub = try #require(scene.drops.first { !$0.big })
        #expect(nub.cx == 152 && nub.w == 11)
    }

    @Test("Under Reduce Motion there are no drops")
    func reduceMotion() throws {
        let scene = try #require(SealScene.make(run: run(), rects: rects, width: 1200, reduceMotion: true))
        #expect(scene.drops.isEmpty)
        #expect(scene.reduceMotion)
    }

    @Test("The chip lands on its jar, held inside the part of the Shelf on screen")
    func chipLanding() {
        let shelf = CGRect(x: 0, y: 56, width: 120, height: 400)
        // A jar on screen: its shoulder.
        let seen = CGRect(x: 31, y: 100, width: 41, height: 58)
        #expect(SealScene.chipLanding(on: seen, within: shelf) == CGPoint(x: 31 + 20.5 - 8, y: 104))
        // A jar scrolled out below the rail: held to the column's foot.
        let below = CGRect(x: 31, y: 900, width: 41, height: 58)
        #expect(SealScene.chipLanding(on: below, within: shelf) == CGPoint(x: 43.5, y: 436))
        // Above it: held to the column's head.
        let above = CGRect(x: 31, y: -200, width: 41, height: 58)
        #expect(SealScene.chipLanding(on: above, within: shelf).y == 60)
        // No column published: the jar's own shoulder.
        #expect(SealScene.chipLanding(on: below, within: nil) == CGPoint(x: 43.5, y: 904))
    }

    @Test("A phase knows its run, and only idle is idle")
    func phases() {
        let r = run()
        #expect(SealPhase.idle.run == nil && SealPhase.idle.isIdle)
        for phase in [SealPhase.started(r), .frozen(r), .failed(r)] {
            #expect(phase.run == r)
            #expect(!phase.isIdle)
        }
    }
}
