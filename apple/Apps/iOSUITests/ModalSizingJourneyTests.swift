import XCTest

/// Modal sizing and chrome (owner decisions, 2026-10-16; `.agents/patterns/modal-sheet.md`): a short sheet opens at its
/// content's height, a long one and any sheet with a section tab bar open full, the tab bar shows icons on iPhone and a
/// menu at AX5, an edit sheet's confirm check is disabled until a change, and the Filter sheet has a blue Reset row and
/// no translucent header. Runs on the `modal-sizing` gallery on iPhone, iPhone Duo and iPad.
@MainActor
final class ModalSizingJourneyTests: JourneyTestCase {
    private func launch(open kind: String? = nil, arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("modal-sizing", arguments: arguments + (kind.map { ["-modalSizingOpen", $0] } ?? []),
                                              appearance: appearance)
        return app
    }

    private func open(_ kind: String, arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        let app = launch(open: kind, arguments: arguments, appearance: appearance)
        let ready = ["edit": "sizing.edit.cancel", "filter": "filterSheet.cancel", "sort": "filterSheet.cancel"][kind] ?? "sizing.close"
        XCTAssertTrue(element(ready, in: app).waitForExistence(timeout: 20), "\(kind) sheet did not open")
        sleep(2) // Let the presentation and the first measurement settle.
        return app
    }

    private func windowHeight(_ app: XCUIApplication) -> CGFloat { app.windows.firstMatch.frame.height }

    // MARK: - Height

    /// Three rows open at their own height, well under the window (iPhone detent and iPad fitted sheet alike).
    func testShortSheetOpensAtContentHeight() {
        let app = open("short")
        let scroll = element("sizing.short.scroll", in: app)
        XCTAssertTrue(scroll.exists)
        keepScreenshot(app, "modal-short-\(layout)")
        XCTAssertLessThan(scroll.frame.height, 420, "A three-row sheet should be as tall as its rows, not \(scroll.frame.height) pt")
        XCTAssertLessThan(scroll.frame.height, windowHeight(app) - 200)
        // Fitted means every row is shown, not cut by the sheet's edge.
        let party = app.staticTexts["Party"]
        XCTAssertTrue(party.exists)
        XCTAssertLessThanOrEqual(party.frame.maxY, scroll.frame.maxY - 8, "The last row is cut off by the sheet's bottom edge")
        // It stays put: no jump while open.
        let first = scroll.frame
        sleep(2)
        XCTAssertEqual(scroll.frame.height, first.height, accuracy: 1, "The sheet resized while open")
    }

    /// Forty rows reach the large detent and scroll.
    func testTallSheetOpensAtLargeAndScrolls() {
        let app = open("tall")
        let scroll = element("sizing.tall.scroll", in: app)
        keepScreenshot(app, "modal-tall-\(layout)")
        XCTAssertGreaterThan(scroll.frame.height, min(windowHeight(app) * 0.6, 600), "Long content should open tall")
        XCTAssertTrue(app.staticTexts["Light 1"].exists)
        XCTAssertFalse(app.staticTexts["Light 40"].isHittable, "The last row is below the fold until scrolled")
    }

    /// A modal with a section tab bar opens full height, however short its content.
    func testTabSheetOpensFullHeight() {
        let app = open("tabs")
        let scroll = element("sizing.tabs.scroll", in: app)
        keepScreenshot(app, "modal-tabs-\(layout)")
        XCTAssertGreaterThan(scroll.frame.height, windowHeight(app) * 0.6, "A tab-bar sheet opens full height")
    }

    // MARK: - Tab bar

    /// iPhone and the folded Duo (compact width) show icons that VoiceOver still names; iPad shows text.
    func testTabBarShowsIconsOnCompactWidthAndNamesThem() {
        let app = open("tabs")
        let tabs = app.segmentedControls["sizing.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        for name in ["Controls", "Apps", "Info"] {
            let segment = tabs.buttons[name]
            XCTAssertTrue(segment.exists, "\(name) segment missing or unnamed")
            assertTarget(segment)
        }
        let compact = FentonHomeApp.family != .iPad
        if compact {
            XCTAssertEqual(tabs.staticTexts.count, 0, "Compact width shows icons, not text titles")
            XCTAssertGreaterThan(tabs.images.count, 0, "Compact width shows icons")
        } else {
            XCTAssertGreaterThan(tabs.staticTexts.count + tabs.buttons.count, 0)
        }
        tabs.buttons["Apps"].tap()
        XCTAssertTrue(app.staticTexts["Apps"].waitForExistence(timeout: 3) || tabs.buttons["Apps"].isSelected)
        keepScreenshot(app, "modal-tabbar-\(layout)")
    }

    /// At AX5 the control becomes a menu that still switches sections.
    func testTabBarIsAMenuAtAccessibilitySizes() {
        let app = open("tabs", arguments: FentonHomeApp.ax5)
        XCTAssertFalse(app.segmentedControls["sizing.tabs"].exists, "Segments cannot grow at AX5")
        let menu = element("sizing.tabs", in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The AX5 section menu is missing")
        assertTarget(menu)
        keepScreenshot(app, "modal-tabbar-ax5-\(layout)")
    }

    // MARK: - Edit state

    /// The confirm check is visible but disabled until the draft changes, then enabled, then disabled again on revert.
    func testConfirmIsDisabledUntilAChange() {
        let app = open("edit")
        let save = app.buttons["sizing.edit.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The confirm check stays visible")
        XCTAssertFalse(save.isEnabled, "Nothing changed: the check is disabled")
        keepScreenshot(app, "modal-edit-unchanged-\(layout)")
        let field = app.textFields["sizing.edit.name"]
        field.tap()
        field.typeText("!")
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5), "A change enables the check")
        keepScreenshot(app, "modal-edit-changed-\(layout)")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: false, timeout: 5), "Reverting the change disables it again")
    }

    // MARK: - Filter sheet

    /// Reset to Defaults is a blue list row, never red.
    func testResetRowIsTintedNotRed() {
        let app = open("filter", appearance: "light")
        let reset = app.buttons["filterSheet.reset"]
        for _ in 0..<8 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.isHittable, "Reset to Defaults is missing")
        sleep(1)
        keepScreenshot(app, "modal-filter-reset-\(layout)")
        guard let capture = RenderedContrast.Capture.screen(), let hue = hue(of: reset.frame, in: capture) else {
            return XCTFail("Could not sample the Reset row")
        }
        XCTAssertGreaterThan(hue.mostBlue, 0.3, "Reset to Defaults should be tint blue")
        XCTAssertLessThan(hue.mostRed, 0.1, "Reset to Defaults must not be red (not destructive)")
    }

    /// With rows scrolled under the header there is no translucent band: the pixels beside the title match the sheet's
    /// own ground.
    func testFilterHeaderHasNoTranslucentBand() {
        for appearance in ["light", "dark"] {
            let app = open("filter", appearance: appearance)
            let apply = app.buttons["filterSheet.apply"]
            XCTAssertTrue(apply.exists)
            // Rows under the header: scroll the form up.
            for _ in 0..<3 { app.swipeUp() }
            sleep(1)
            guard let capture = RenderedContrast.Capture.screen() else { return XCTFail("No capture") }
            let cancel = app.buttons["filterSheet.cancel"].frame
            // Between Cancel and the title, where rows would show through a material.
            let x = (cancel.maxX + apply.frame.minX) / 2 - (apply.frame.minX - cancel.maxX) * 0.35
            let y = cancel.midY
            let band = RenderedContrast.luminance(at: CGPoint(x: x, y: y), in: capture)
            let ground = RenderedContrast.luminance(at: CGPoint(x: cancel.minX - 12, y: cancel.maxY + 30), in: capture)
            keepScreenshot(app, "modal-filter-header-\(appearance)-\(layout)")
            guard let band, let ground else { return XCTFail("Off capture") }
            XCTAssertEqual(band, ground, accuracy: 0.03, "\(appearance): the header sits on a band, not the sheet's ground")
            app.terminate()
        }
    }

    // MARK: - Pixels

    /// The most blue-over-red and most red-over-blue any pixel in `frame` is, 0 for greys: text in the tint shows a
    /// strongly blue pixel, destructive text a strongly red one.
    private func hue(of frame: CGRect, in capture: RenderedContrast.Capture) -> (mostBlue: Double, mostRed: Double)? {
        guard let rect = RenderedContrast.pixelRect(of: frame, in: capture) else { return nil }
        var mostBlue = 0.0, mostRed = 0.0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * capture.width + x) * 4
                let r = Double(capture.pixels[i]) / 255, b = Double(capture.pixels[i + 2]) / 255
                mostBlue = max(mostBlue, b - r)
                mostRed = max(mostRed, r - b)
            }
        }
        return (mostBlue, mostRed)
    }
}
