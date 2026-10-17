import XCTest

/// The header fade still follows the page's scroll after its offset moved from SwiftUI's `onScrollGeometryChange` to a
/// UIKit observer (`UIKitScrollOffset`): the tracked offset is 0 at rest, grows with the first 40 points of a scroll, stops at
/// 41 however far the page goes, and returns to 0 at the top, on a `List` page (Settings) and a `ScrollView` page (Security).
/// The Reduce Transparency and Increase Contrast fallbacks (a hard edge, no ramp) are `HeaderEdgeFade.ramp`, unchanged and
/// covered by `HeaderEdgeFadeTests`.
final class HeaderFadeJourneyTests: JourneyTestCase {
    private func launch(gallery: String, scroll: String) -> (XCUIApplication, XCUIElement, XCUIElement) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = gallery
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        app.launchEnvironment["FENTON_FADE_PROBE"] = "1"
        app.launch()
        let page = element(scroll, in: app)
        XCTAssertTrue(page.waitForExistence(timeout: 30), "\(gallery) did not open")
        let probe = element("diagnostics.headerFade", in: app)
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "The fade's scroll observer did not find the page's scroll view")
        return (app, page, probe)
    }

    private func offset(_ probe: XCUIElement) -> Int { Int(probe.value as? String ?? "") ?? -99 }

    /// Waits for the probe's value to read `expected`.
    private func waitFor(_ expected: String, _ probe: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: probe)], timeout: timeout) == .completed
    }

    private func check(_ gallery: String, scroll: String) {
        let (_, page, probe) = launch(gallery: gallery, scroll: scroll)
        XCTAssertEqual(offset(probe), 0, "The fade rests at 0 at the top of \(gallery)")
        page.swipeUp(velocity: .slow)
        XCTAssertTrue(waitFor("41", probe) || offset(probe) > 0,
                      "Scrolling did not move the fade (\(probe.value as? String ?? "nil"))")
        for _ in 0..<3 { page.swipeUp(velocity: .fast) }
        XCTAssertEqual(offset(probe), 41, "The fade stops at the ramp however far the page scrolls")
        for _ in 0..<8 { page.swipeDown(velocity: .fast) }
        XCTAssertTrue(waitFor("0", probe), "The fade returns to rest at the top (\(probe.value as? String ?? "nil"))")
    }

    func testListPageFadeFollowsTheScroll() { check("settings", scroll: "settings.list") }

    func testScrollViewPageFadeFollowsTheScroll() { check("security", scroll: "security.scroll") }
}
