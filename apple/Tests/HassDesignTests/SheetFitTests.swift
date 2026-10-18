import SwiftUI
import Testing
@testable import HassDesign

/// Content-fitted sheet height (owner, 2026-10-16): the pure decisions behind `hassSheet(height: .fitted)` and the edit
/// state of the confirm check.
@MainActor
struct SheetFitTests {
    // MARK: - Detent

    @Test func noMeasurementIsProvisional() {
        #expect(SheetFit.detent(contentHeight: nil, availableHeight: 800) == .provisional)
        #expect(SheetFit.detent(contentHeight: .nan, availableHeight: 800) == .provisional)
    }

    @Test func shortContentGetsItsOwnHeight() {
        #expect(SheetFit.detent(contentHeight: 360.2, availableHeight: 800) == .height(361))
    }

    @Test func tooShortAReadingIsRaisedToTheMinimum() {
        #expect(SheetFit.detent(contentHeight: 40, availableHeight: 800) == .height(SheetFit.minimumHeight))
    }

    @Test func contentReachingLargeIsLarge() {
        #expect(SheetFit.detent(contentHeight: 800, availableHeight: 800) == .large)
        #expect(SheetFit.detent(contentHeight: 2400, availableHeight: 800) == .large)
        // Within the snap distance: a custom detent a hair under large would leave a sliver of the page.
        #expect(SheetFit.detent(contentHeight: 800 - SheetFit.largeSnap + 1, availableHeight: 800) == .large)
        #expect(SheetFit.detent(contentHeight: 800 - SheetFit.largeSnap - 1, availableHeight: 800) != .large)
    }

    @Test func noWindowMeansLarge() {
        #expect(SheetFit.detent(contentHeight: 300, availableHeight: 0) == .large)
    }

    // MARK: - Readings

    @Test func smallChangesDoNotMoveTheSheet() {
        #expect(SheetFit.shouldUpdate(from: nil, to: 300))
        #expect(!SheetFit.shouldUpdate(from: 300, to: 301))
        #expect(SheetFit.shouldUpdate(from: 300, to: 302))
        #expect(!SheetFit.shouldUpdate(from: 300, to: 0))
        #expect(!SheetFit.shouldUpdate(from: 300, to: .infinity))
    }

    @Test func wantedHeightAddsTheInsets() {
        #expect(SheetFit.wantedHeight(contentHeight: 200, topInset: 56, bottomInset: 34) == 290)
        #expect(SheetFit.wantedHeight(contentHeight: -5, topInset: -1, bottomInset: 34) == 34)
    }

    @Test func horizontalRailsAndTinyContainersAreNotThePageScroller() {
        #expect(SheetFit.isPageScroller(contentWidth: 390, containerWidth: 390, containerHeight: 700))
        #expect(!SheetFit.isPageScroller(contentWidth: 900, containerWidth: 390, containerHeight: 700), "A chip rail scrolls sideways")
        #expect(!SheetFit.isPageScroller(contentWidth: 390, containerWidth: 390, containerHeight: 60), "A small carousel")
    }

    // MARK: - The channel

    @Test func theFirstPageOwnsTheSheetHeight() {
        var accepted: [CGFloat] = []
        let model = SheetFitModel { accepted.append($0) }
        let root = UUID(), pushed = UUID()
        model.report(320, from: root)
        model.report(900, from: pushed)
        #expect(model.contentHeight == 320, "A pushed page must not resize the sheet")
        model.report(380, from: root)
        #expect(model.contentHeight == 380, "The root page's content change resizes it")
        #expect(accepted == [320, 380])
    }

    @Test func aPhoneFitsToItsContentAndSafeAreasNotItsOwnHeight() {
        // The bathroom fan sheet's trace (iPhone 17 Pro, 2026-10-17): content 328, a 314 pt scroller that did not grow with
        // the sheet, safe areas 70 and 34. Counting the sheet's own height asked for 14 pt more each time, up to large.
        let model = SheetFitModel()
        model.setSafeInsets(top: 70, bottom: 34)
        for sheet: CGFloat in [451, 465, 479, 778] {
            model.setSheetHeight(sheet)
            model.report(SheetFit.Reading(content: 328, viewport: 314), from: UUID())
        }
        #expect(model.contentHeight == 432, "Content plus the safe areas, however tall the sheet is")
    }

    @Test func aRegularWidthSheetCountsItsHeaderBelowTheScroller() {
        // An iPad form sheet whose scroller sits below a 90 pt header and reports no top inset.
        let pad = SheetFitModel()
        pad.usesSheetEstimate = true
        pad.setSheetHeight(500)
        pad.report(SheetFit.Reading(content: 300, viewport: 410), from: UUID())
        #expect(pad.contentHeight == 390)
        let phone = SheetFitModel()
        phone.setSheetHeight(500)
        phone.report(SheetFit.Reading(content: 300, viewport: 410), from: UUID())
        #expect(phone.contentHeight == 300, "A phone does not use the sheet estimate")
    }

    @Test func aRememberedHeightIsTheStartingPoint() {
        let model = SheetFitModel(initial: 410)
        #expect(model.contentHeight == 410)
        model.report(411, from: UUID())
        #expect(model.contentHeight == 410, "Within hysteresis of the remembered height")
    }

    @Test func memoryIsPerCallSite() {
        SheetFitMemory.reset()
        SheetFitMemory.remember(300, for: "A.swift:10")
        #expect(SheetFitMemory.height(for: "A.swift:10") == 300)
        #expect(SheetFitMemory.height(for: "A.swift:11") == nil)
        SheetFitMemory.reset()
    }

    // MARK: - Edit state

    @Test func confirmNeedsAValidChangedIdleDraft() {
        #expect(SheetEditState.canConfirm(isValid: true, hasChanges: true))
        #expect(!SheetEditState.canConfirm(isValid: true, hasChanges: false), "Nothing changed")
        #expect(!SheetEditState.canConfirm(isValid: false, hasChanges: true), "An empty name")
        #expect(!SheetEditState.canConfirm(isValid: true, hasChanges: true, isBusy: true), "A save in flight")
    }

    // MARK: - Rendering

    @Test func sheetsRenderFittedAndFull() {
        let content = HassModal("Short") { ScrollView { Text("Row") } }
        #expect(ImageRenderer(content: content.hassSheet().frame(width: 390, height: 400)).cgImage != nil)
        #expect(ImageRenderer(content: content.hassSheet(.page, height: .full).frame(width: 390, height: 400)).cgImage != nil)
        #expect(ImageRenderer(content: content.hassSheet(appearance: .dark).frame(width: 390, height: 400)).cgImage != nil)
    }
}
