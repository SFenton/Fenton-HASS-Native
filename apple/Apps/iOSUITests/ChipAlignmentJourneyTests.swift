import XCTest

/// The status chip row starts at the page's leading margin, whether it overflows or not (owner, 2026-10-17: "Security
/// chips are not left-aligned. Even if all chips fit on screen, they still need to be left aligned."). The compact rail is
/// a hosted `UIScrollView`, whose hosting view centred a row narrower than the scroll view; the regular-width rail wraps
/// with `FlowLayout`, whose rows start at the leading edge (`.agents/patterns/status-rail.md`).
///
/// Each page is checked on iPhone, the folded Duo and iPad in portrait and landscape (the unfolded Duo is not scriptable;
/// its rule is `ChipRailMetrics` and `ChipRailTests`): the first chip's leading edge is the page's content margin from the
/// page's own leading edge, and so is the first chip of every wrapped row.
final class ChipAlignmentJourneyTests: JourneyTestCase {
    /// The page's content margin (`HassTokens.Spacing.l`).
    private let margin: CGFloat = 16

    /// The orientations to check: iPad turns, the phones are portrait.
    private var orientations: [UIDeviceOrientation] {
        FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.portrait]
    }

    private func launch(gallery: String, environment: [String: String] = [:], ready: String) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = gallery
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        XCTAssertTrue(element(ready, in: app).waitForExistence(timeout: 30), "\(gallery) did not open")
        return app
    }

    /// The chips whose identifier starts with `prefix`, by leading edge then top.
    private func chips(_ prefix: String, in app: XCUIApplication) -> [XCUIElement] {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        return query.allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 0 }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// Every row of chips begins `margin` points inside `page`'s leading edge.
    private func assertChipsStartAtTheMargin(_ prefix: String, page: String, in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let pageFrame = element(page, in: app).frame
        let all = chips(prefix, in: app)
        XCTAssertFalse(all.isEmpty, "No \(prefix) chips on \(layout)", file: file, line: line)
        // A row is the chips sharing a top; the scrolling rail is one row, the wrapped rail several.
        var rows: [CGFloat: [XCUIElement]] = [:]
        for chip in all { rows[chip.frame.minY.rounded(), default: []].append(chip) }
        for (_, row) in rows {
            guard let first = row.min(by: { $0.frame.minX < $1.frame.minX }) else { continue }
            XCTAssertEqual(first.frame.minX - pageFrame.minX, margin, accuracy: 1,
                           "The first \(prefix) chip in its row (\(first.label)) is not at the content margin on \(layout)", file: file, line: line)
        }
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        guard XCUIDevice.shared.orientation != orientation else { return }
        XCUIDevice.shared.orientation = orientation
        sleep(2) // the rail lays out again for the new width
    }

    /// Security's two chips fit on every phone: they still start at the margin (this was the reported bug).
    func testSecurityChipsStartAtTheLeadingMargin() {
        let app = launch(gallery: "security", ready: "security.chip.security")
        for orientation in orientations {
            rotate(to: orientation)
            assertChipsStartAtTheMargin("security.chip.", page: "security.scroll", in: app)
        }
    }

    /// Home's six chips overflow a phone and wrap on an iPad.
    func testHomeChipsStartAtTheLeadingMargin() {
        let app = launch(gallery: "performance", environment: ["FENTON_GALLERY_PERF": "chips"], ready: "home.chip.lights")
        for orientation in orientations {
            rotate(to: orientation)
            assertChipsStartAtTheMargin("home.chip.", page: "perf.chips", in: app)
        }
    }

    /// A room page's rail.
    func testRoomChipsStartAtTheLeadingMargin() {
        let app = launch(gallery: "rooms", environment: ["FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_ROOM": "living-room"],
                         ready: "room.scroll.living-room")
        for orientation in orientations {
            rotate(to: orientation)
            assertChipsStartAtTheMargin("room.chip.", page: "room.scroll.living-room", in: app)
        }
    }
}
