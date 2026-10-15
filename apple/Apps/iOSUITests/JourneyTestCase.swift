import XCTest

/// The base every journey subclasses: setup, orientation and the gallery helpers each journey used to redeclare
/// (`.agents/audit/tests.md` findings 1 and 2).
///
/// A run asks for landscape with `TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape` (the older `FENTON_ORIENTATION`
/// also works). Only the families in ``rotatingFamilies`` turn; every test ends back in portrait.
@MainActor
class JourneyTestCase: XCTestCase {
    /// Whether this run is the landscape pass.
    static var wantsLandscape: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["FENTON_UITEST_ORIENTATION"] == "landscape" || environment["FENTON_ORIENTATION"] == "landscape"
    }

    /// The families a landscape run rotates. iPhone is portrait-locked; override to add the unfolded Duo.
    class var rotatingFamilies: [FentonHomeApp.Family] { [.iPad] }

    /// `iphone`, `ipad-landscape` and so on, for screenshot names.
    var layout: String {
        let landscape = Self.wantsLandscape && Self.rotatingFamilies.contains(FentonHomeApp.family) ? "-landscape" : ""
        return "\(FentonHomeApp.family)\(landscape)"
    }

    override func setUp() {
        continueAfterFailure = false
        if Self.rotatingFamilies.contains(FentonHomeApp.family), Self.wantsLandscape {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            if Self.rotatingFamilies.contains(FentonHomeApp.family) { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Shell navigation

    /// Opens a root section through whichever navigation the window shows (`ShellNavigationStyle`): the tab bar
    /// (iPhone), the folded iPhone Duo's vertical bar (a toolbar to XCUITest), or the flyout in regular width
    /// (iPad, unfolded Duo). Compact windows also show the menu button, so a visible bar item wins.
    /// - Parameters:
    ///   - section: The `AppSection` raw value (`security`), whose flyout row is `nav.<section>`.
    ///   - title: The section's visible name (`Security`), which labels its bar item.
    func openSection(_ section: String, title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let items = [app.tabBars.buttons[title], app.toolbars.buttons[title]]
        let menu = app.buttons["nav.open"]
        let start = Date()
        let deadline = start.addingTimeInterval(10)
        repeat {
            if let item = items.first(where: { $0.exists && $0.isHittable }) {
                item.tap()
                return
            }
            // A bar that exists but stays off screen (a regular-width window) gets two seconds to show.
            if menu.exists, menu.isHittable, !items.contains(where: \.exists) || Date().timeIntervalSince(start) > 2 { break }
            usleep(250_000)
        } while Date() < deadline
        XCTAssertTrue(menu.exists, "\(title) has no tab and the window has no menu", file: file, line: line)
        menu.tap()
        XCTAssertTrue(element("nav.flyout", in: app).waitForExistence(timeout: 5), "Menu did not open", file: file, line: line)
        app.buttons["nav.\(section)"].tap()
        XCTAssertTrue(element("nav.flyout", in: app).waitForNonExistence(timeout: 5), "Menu stayed open", file: file, line: line)
    }

    // MARK: - Gallery helpers

    /// The first element of any type with accessibility identifier `id`.
    func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The gallery's last recorded service call, without the `Last call: ` prefix.
    func lastCall(in app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].firstMatch.label.replacing("Last call: ", with: "")
    }

    /// How ``expectLastCall(_:matching:in:timeout:file:line:)`` compares.
    enum CallMatch: String { case equals = "==", beginsWith = "BEGINSWITH", contains = "CONTAINS" }

    /// Waits until the gallery's last call matches `expected` (`Last call: ` is added for `.equals` and `.beginsWith`).
    func expectLastCall(_ expected: String, matching match: CallMatch = .equals, in app: XCUIApplication, timeout: TimeInterval = 10,
                        file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let value = match == .contains ? expected : "Last call: \(expected)"
        let predicate = NSPredicate(format: "label \(match.rawValue) %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Last call was '\(label.label)', expected \(match) '\(expected)'", file: file, line: line)
    }

    /// Asserts a 44 pt minimum hit target (43 allows for the simulator's rounding).
    func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }
}
