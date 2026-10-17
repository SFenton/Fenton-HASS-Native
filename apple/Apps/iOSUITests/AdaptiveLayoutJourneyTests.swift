import XCTest

/// Layout that adapts to the window (plan Phase 4, decisions 1 to 5; `.agents/design/apple/ipados.md`, `duo.md`):
/// grids reach four columns on iPad, and status chips wrap in regular width and scroll in compact width. Every test names what it expects per device family; the unfolded Duo cannot be
/// driven here (the simulator may not unfold), so its hinge rules are unit tested (`HomeColumnsTests`, `ChipRailTests`,
/// `DynamicGridHingeTests`).
@MainActor
final class AdaptiveLayoutJourneyTests: JourneyTestCase {
    /// Whether the window is regular width: iPad, and the unfolded Duo (669 pt portrait, 951 pt landscape); never the
    /// folded Duo's outer display (466 pt) or an iPhone. Read from the window, as the app reads its size class.
    private func isRegular(_ app: XCUIApplication) -> Bool { app.windows.firstMatch.frame.width >= 600 }

    // MARK: Grids (decision 1)

    /// The Chores quick links in the gallery (fixture state): four tiles across on iPad in either orientation, two on a
    /// phone. Tiles on one row share a `minY`.
    func testChoresQuickLinksGrowToFourColumnsOnIPad() {
        let app = FentonHomeApp.launchGallery("chores")
        XCTAssertTrue(app.buttons["fab.add"].waitForExistence(timeout: 10), "Chores gallery did not open")
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chores.link.'")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(tiles.count, 4, "Quick links missing")
        let top = tiles.map(\.frame.minY).min() ?? 0
        let firstRow = tiles.filter { abs($0.frame.minY - top) < 2 }
        if isRegular(app) {
            XCTAssertGreaterThanOrEqual(firstRow.count, 4, "iPad shows \(firstRow.count) quick links across, expected at least 4")
            let widths = Set(firstRow.map { Int($0.frame.width.rounded()) })
            XCTAssertLessThanOrEqual(widths.count, 2, "Tiles in a row differ in width: \(widths)")
        } else {
            XCTAssertGreaterThanOrEqual(firstRow.count, 2)
            XCTAssertLessThan(firstRow.count, 4, "A phone should not squeeze \(firstRow.count) tiles across")
        }
        for tile in firstRow { assertTarget(tile) }
        keepShot(app, "g4-chores-\(layout)")
    }

    /// A room page lays two sections side by side on iPad (two tiles each: four across), one column on a phone.
    func testRoomSectionsSitSideBySideOnIPad() {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "rooms"
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchEnvironment["FENTON_GALLERY_ROOM"] = "living-room"
        app.launch()
        XCTAssertTrue(element("room.scroll.living-room", in: app).waitForExistence(timeout: 30), "Room did not open")
        sleep(1)
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'room.card.'")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(cards.count, 2)
        let top = cards.map(\.frame.minY).min() ?? 0
        let firstRow = cards.filter { abs($0.frame.minY - top) < 2 }
        if isRegular(app) {
            XCTAssertGreaterThanOrEqual(firstRow.count, 3, "iPad shows \(firstRow.count) tiles across, expected the sections side by side")
        } else {
            XCTAssertLessThanOrEqual(firstRow.count, 2)
        }
        keepShot(app, "g4-room-\(layout)")
    }

    // MARK: Chips (decision 2)

    /// Home's six chips wrap onto rows that all fit the window in regular width; in compact width they scroll in one row.
    func testHomeChipsWrapInRegularWidthAndScrollInCompact() throws {
        let app = try FentonHomeApp.launchSignedIn()
        sleep(2)
        let chips = ["lights", "security", "climate", "occupancy", "contacts", "airQuality"].map { app.buttons["home.chip.\($0)"] }
        for chip in chips { XCTAssertTrue(chip.exists, chip.identifier) }
        let window = app.windows.firstMatch.frame
        let rows = Set(chips.map { Int($0.frame.minY.rounded()) })
        if isRegular(app) {
            for chip in chips {
                XCTAssertGreaterThanOrEqual(chip.frame.minX, window.minX, "\(chip.identifier) starts off screen")
                XCTAssertLessThanOrEqual(chip.frame.maxX, window.maxX, "\(chip.identifier) runs off screen")
                assertTarget(chip)
            }
            // Wrapping, not scrolling: six chips take one row in a wide window, two on iPad portrait, three in the unfolded
            // Duo's leading half.
            XCTAssertLessThanOrEqual(rows.count, 3, "Chips took \(rows.count) rows")
            XCTAssertGreaterThanOrEqual(rows.count, 1)
        } else {
            XCTAssertEqual(rows.count, 1, "Compact chips scroll in one row")
        }
        keepShot(app, "g4-home-chips-\(layout)")
    }

    // MARK: Quick Links (decision 3, reversed 2026-10-16)

    // Quick Links is a header button beside Profile on every page of every window now, so the floating circle's journeys
    // are gone; `ShellJourneyTests` covers the button on every tab root and on a pushed page, on all three families.

    // MARK: Home on the hinge (decision 5)

    /// Unfolded Duo in landscape: chips and weather lead, cameras trail, and nothing crosses the hinge (it sits near the
    /// window's middle; the chip row stops 24 pt short of it). Elsewhere Home is one column. Not a skip when it does not
    /// apply: it passes by checking the one-column layout.
    func testHomeSplitsOnTheHingeOnlyWhenUnfoldedInLandscape() throws {
        let app = try FentonHomeApp.launchSignedIn()
        sleep(3)
        let window = app.windows.firstMatch.frame
        let chip = app.buttons["home.chip.lights"]
        let camera = app.buttons["home.camera.front_door"]
        XCTAssertTrue(camera.waitForExistence(timeout: 10), "No camera tile")
        let unfoldedLandscape = FentonHomeApp.family == .iPhoneDuo && window.width > window.height && window.width >= 900
        if unfoldedLandscape {
            XCTAssertLessThan(chip.frame.maxX, window.midX - 24, "Chips reach the hinge")
            XCTAssertGreaterThan(camera.frame.minX, window.midX, "Cameras are not in the trailing half")
            for id in ["lights", "security", "climate", "occupancy", "contacts", "airQuality"] {
                let rail = app.buttons["home.chip.\(id)"]
                XCTAssertLessThan(rail.frame.maxX, window.midX - 24, "\(id) chip crosses the hinge")
            }
        } else {
            // One column: the cameras sit below the chips, not beside them.
            XCTAssertGreaterThan(camera.frame.minY, chip.frame.maxY, "Home is split without a hinge")
        }
        keepShot(app, "g4-home-\(layout)-\(unfoldedLandscape ? "split" : "single")")
    }

    // MARK: Helpers

    /// Saves a screenshot as an attachment for design review (never committed).
    private func keepShot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
