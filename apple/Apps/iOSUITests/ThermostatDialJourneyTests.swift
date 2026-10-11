import XCTest

/// The shared thermostat dial in the debug gallery: drag, tap, VoiceOver semantics, audits and
/// screenshots on iPhone, iPhone Duo and iPad (`.agents/patterns/thermostat-dial.md`).
@MainActor
final class ThermostatDialJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait } }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("thermostat-dial", arguments: arguments)
        XCTAssertTrue(app.staticTexts["gallery.lastCommit"].waitForExistence(timeout: 10))
        return app
    }

    private func card(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["gallery.thermostat.\(id)"].firstMatch
    }

    private func handle(_ name: String, in card: XCUIElement) -> XCUIElement {
        card.descendants(matching: .any)["thermostatDial.handle.\(name)"].firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func lastCommit(_ app: XCUIApplication) -> String { app.staticTexts["gallery.lastCommit"].label }

    // MARK: - Semantics

    /// Each handle is a named, adjustable, 44 pt+ element; the readout is one element with name, action
    /// and current temperature; the unavailable dial has no handles.
    func testHandlesAndReadoutAreAccessible() {
        let app = launch()
        let heating = card("heating", in: app)
        let target = handle("target", in: heating)
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.label, "Living Room target temperature")
        XCTAssertEqual(target.value as? String, "72 degrees")
        XCTAssertGreaterThanOrEqual(target.frame.width, 43)
        XCTAssertGreaterThanOrEqual(target.frame.height, 43)
        let readout = heating.descendants(matching: .any)["thermostatDial.readout"].firstMatch
        XCTAssertEqual(readout.label, "Living Room thermostat, Heating, currently 68.5°F")

        let range = card("range", in: app)
        scrollTo(range, in: app)
        XCTAssertEqual(handle("low", in: range).label, "Whole Home heat to")
        XCTAssertEqual(handle("high", in: range).label, "Whole Home cool to")

        let unavailable = card("unavailable", in: app)
        scrollTo(unavailable, in: app)
        XCTAssertFalse(unavailable.descendants(matching: .any)["thermostatDial.handle.target"].exists)
    }

    // MARK: - Interaction

    /// Dragging the single handle to the top of the ring commits the middle of the range (70°).
    func testDraggingTheHandleCommitsOnRelease() {
        let app = launch()
        let heating = card("heating", in: app)
        let target = handle("target", in: heating)
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let dial = heating.descendants(matching: .any)["thermostatDial"].firstMatch
        let top = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: top)
        XCTAssertTrue(app.staticTexts["gallery.lastCommit"].wait(for: \.label, toEqual: "Last commit: heating single 70", timeout: 3),
                      lastCommit(app))
        XCTAssertEqual(target.value as? String, "70 degrees")
    }

    // VoiceOver's adjustable action (swipe up/down on a handle) is covered by the hosted
    // `Apps/iOSTests/ThermostatDialAccessibilityTests`: XCUITest can only adjust slider elements.

    /// Tapping the ring past the cool-to handle moves that handle there.
    func testTappingTheRingMovesTheNearestHandle() {
        let app = launch()
        let range = card("range", in: app)
        scrollTo(range, in: app)
        let dial = range.descendants(matching: .any)["thermostatDial"].firstMatch
        // Right side of the ring, level with the centre: 86.5° on a 45–95 ring.
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + 0.453 * (dial.frame.width - 40) / dial.frame.width, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["gallery.lastCommit"].wait(for: \.label, toEqual: "Last commit: range range 68-86.5", timeout: 3),
                      lastCommit(app))
    }

    // MARK: - Audits and screenshots

    /// Full accessibility audit (with the AX5 relaunch) in every supported orientation, plus a screenshot
    /// of each fixture for the PR.
    func testGalleryAuditsAndScreenshots() throws {
        let app = launch()
        try auditAndCapture(app, orientation: "portrait")
        guard FentonHomeApp.family == .iPad else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        try auditAndCapture(app, orientation: "landscape")
    }

    private func auditAndCapture(_ app: XCUIApplication, orientation: String) throws {
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            sleep(1)
            return large
        }
        let fresh = launch()
        for id in ["heating", "range", "cooling", "off", "unavailable"] {
            scrollTo(card(id, in: fresh), in: fresh)
            sleep(1)
            let shot = XCTAttachment(screenshot: fresh.screenshot())
            shot.name = "thermostat-dial-\(FentonHomeApp.family)-\(orientation)-\(id)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
