import CoreGraphics
@testable import HassDesign
import SwiftUI
import Testing

/// The header fade's geometry (pattern: `.agents/patterns/header-edge-fade.md`).
struct HeaderEdgeFadeTests {
    @Test func headerIsTheLargerReadingNeverTheirSum() {
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: 96, containerOffset: 0) == 96)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: 56, containerOffset: 56) == 56)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: 0, containerOffset: 120) == 120)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: -4, containerOffset: -8) == 0)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: .nan, containerOffset: 30) == 30)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: .infinity, containerOffset: .nan) == 0)
    }

    @Test func fadeGrowsLinearlyOverTheFirstFortyPoints() {
        #expect(HeaderEdgeFade.rampHeight == 40)
        #expect(HeaderEdgeFade.progress(scrollOffset: 0) == 0)
        #expect(HeaderEdgeFade.progress(scrollOffset: -30) == 0)
        #expect(HeaderEdgeFade.progress(scrollOffset: 10) == 0.25)
        #expect(HeaderEdgeFade.progress(scrollOffset: 40) == 1)
        #expect(HeaderEdgeFade.progress(scrollOffset: 400) == 1)
        #expect(HeaderEdgeFade.progress(scrollOffset: .nan) == 0)
    }

    @Test func hardEdgeIsClearAsSoonAsContentScrolls() {
        #expect(HeaderEdgeFade.progress(scrollOffset: 0, rampHeight: 0) == 0)
        #expect(HeaderEdgeFade.progress(scrollOffset: 1, rampHeight: 0) == 1)
    }

    @Test func edgeIsOpaqueAtRestAndClearOnceScrolled() {
        #expect(HeaderEdgeFade.edgeOpacity(progress: 0) == 1)
        #expect(HeaderEdgeFade.edgeOpacity(progress: 0.25) == 0.75)
        #expect(HeaderEdgeFade.edgeOpacity(progress: 1) == 0)
        #expect(HeaderEdgeFade.edgeOpacity(progress: 3) == 0)
        #expect(HeaderEdgeFade.edgeOpacity(progress: .nan) == 1)
    }

    @Test func accessibilitySettingsAndMissingScrollTrackingGiveAHardEdge() {
        #expect(HeaderEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: true) == 40)
        #expect(HeaderEdgeFade.ramp(reduceTransparency: true, increaseContrast: false, tracksScroll: true) == 0)
        #expect(HeaderEdgeFade.ramp(reduceTransparency: false, increaseContrast: true, tracksScroll: true) == 0)
        #expect(HeaderEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: false) == 0)
    }

    /// The modifier, the close item and the modal shell render (hosted on macOS by `swift test`).
    @MainActor @Test func modalShellRenders() {
        let view = HassModal("Security System") {
            ScrollView { Text("Content").frame(height: 900) }
        }
        .frame(width: 390, height: 700)
        #expect(ImageRenderer(content: view).cgImage != nil)
        let page = NavigationStack { List { Text("Row") }.headerEdgeFade().hassSheet() }.frame(width: 390, height: 700)
        #expect(ImageRenderer(content: page).cgImage != nil)
        let close = SheetCloseButton(identifier: "x") {}
        #expect(ImageRenderer(content: close).cgImage != nil)
    }
}
