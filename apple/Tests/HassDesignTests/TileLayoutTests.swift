@testable import HassDesign
import SwiftUI
import Testing

/// Tile arrangements (`.agents/design/direction-g.md`, Controls: Tile layout): the shipped default, the accessibility
/// fallback, and the height each arrangement keeps.
@MainActor
struct TileLayoutTests {
    @Test func theShippedLayoutIsTheRow() {
        #expect(TileLayout.standard == .row)
        #expect(EnvironmentValues().tileLayout == .row)
    }

    @Test func aRowAnchorsItsTextAtAccessibilitySizes() {
        #expect(TileLayout.row.resolved(accessibilitySize: false) == .row)
        #expect(TileLayout.row.resolved(accessibilitySize: true) == .anchoredBottom)
        for layout in [TileLayout.anchoredBottom, .centeredStack, .stackedTop] {
            #expect(layout.resolved(accessibilitySize: true) == layout)
            #expect(layout.resolved(accessibilitySize: false) == layout)
        }
    }

    @Test func everyLayoutKeepsA44PointTargetAndTheRowIsTheShortest() {
        let padding: CGFloat = 2 * HassTokens.Spacing.m
        for layout in TileLayout.allCases {
            #expect(layout.minHeight + padding >= 44, "\(layout)")
        }
        #expect(TileLayout.row.minHeight < TileLayout.centeredStack.minHeight)
        #expect(TileLayout.centeredStack.minHeight < TileLayout.anchoredBottom.minHeight)
        #expect(TileLayout.anchoredBottom.minHeight < TileLayout.stackedTop.minHeight)
        #expect(TileLayout.stackedTop.minHeight == 88, "The pre-2026-10-16 arrangement is kept for comparison")
    }

    @Test func layoutsHaveNamesAndStableIds() {
        #expect(Set(TileLayout.allCases.map(\.id)).count == 4)
        #expect(Set(TileLayout.allCases.map(\.title)).count == 4)
    }

    @Test func theChevronGetsRoomAndTheGlyphColumnIsFixed() {
        #expect(GlassTileFace.chevronReserve >= 16)
        #expect(GlassTileFace.rowGlyphWidth >= 28)
    }

    @Test(arguments: TileLayout.allCases, [false, true])
    func everyArrangementRenders(_ layout: TileLayout, _ chevron: Bool) {
        let face = GlassTileFace(title: "Master Bedroom Closet", subtitle: "Occupied", symbol: "figure.walk", tint: .gray,
                                 family: .occupancy, isActive: true, showsChevron: chevron)
            .tileLayout(layout)
            .frame(width: 170)
        #expect(ImageRenderer(content: face).cgImage != nil)
        let accessible = face.environment(\.dynamicTypeSize, .accessibility5)
        #expect(ImageRenderer(content: accessible).cgImage != nil)
    }

    @Test func aColouredFaceRendersOnPagesAndSheets() {
        for surface in [TileSurface.page, .sheet] {
            let face = GlassTileFace(title: "Kitchen", symbol: "stove", tint: .gray, family: .neutral, fillRGB: 0x547F12,
                                     isActive: false, showsChevron: true)
                .environment(\.tileSurface, surface)
                .frame(width: 170)
            #expect(ImageRenderer(content: face).cgImage != nil)
        }
    }

    // MARK: Title reserve

    @Test func noReserveKeepsTheLayoutMinimum() {
        for layout in TileLayout.allCases {
            #expect(TileMetrics.minContentHeight(layout: layout, titleLines: 0) == layout.minHeight)
        }
        #expect(EnvironmentValues().tileTitleLines == 0)
    }

    @Test func twoReservedLinesFitTheGlyphTheGapAndBothLines() {
        let height = TileMetrics.minContentHeight(layout: .anchoredBottom, titleLines: 2)
        #expect(height == TileMetrics.glyphHeight + TileMetrics.glyphGap + 2 * TileMetrics.titleLineHeight)
        #expect(height >= TileLayout.anchoredBottom.minHeight)
        // A taller tile than the shipped row, which is what the Rooms grid asked for.
        #expect(height + 2 * HassTokens.Spacing.m > TileLayout.row.minHeight + 2 * HassTokens.Spacing.m)
    }

    @Test func theReserveGrowsWithTextAndNeverShrinksBelowTheLayout() {
        let small = TileMetrics.minContentHeight(layout: .anchoredBottom, titleLines: 2, glyphHeight: 24, titleLineHeight: 20)
        let accessible = TileMetrics.minContentHeight(layout: .anchoredBottom, titleLines: 2, glyphHeight: 48, titleLineHeight: 40)
        #expect(accessible > small)
        #expect(TileMetrics.minContentHeight(layout: .anchoredBottom, titleLines: 1, glyphHeight: 10, titleLineHeight: 5)
            == TileLayout.anchoredBottom.minHeight)
        #expect(TileMetrics.minContentHeight(layout: .row, titleLines: 3) == 60)
    }

    @Test func aReservingGridRenders() {
        let face = GlassTileFace(title: "Kitchen", symbol: "stove", tint: .gray, family: .neutral, fillRGB: 0x547F12,
                                 isActive: false, showsChevron: true)
            .tileLayout(.anchoredBottom)
            .tileTitleLines(2)
            .frame(width: 170, height: 100)
        #expect(ImageRenderer(content: face).cgImage != nil)
        #expect(ImageRenderer(content: face.environment(\.dynamicTypeSize, .accessibility5)).cgImage != nil)
    }
}
