import XCTest

/// Screenshots of the same sheets in light and dark, for design review next to each other (never committed): each
/// is kept in the result bundle as `g4-<sheet>-<appearance>-<layout>`. No audit and no assertion beyond the sheet
/// opening; the audits are `LightSheetsJourneyTests`.
@MainActor
final class LightSheetCaptureTests: JourneyTestCase {
    private func capture(_ name: String, page: String, environment: [String: String] = [:], arguments: [String] = [],
                         ready: @escaping (XCUIApplication) -> XCUIElement) {
        for appearance in ["light", "dark"] {
            let app = FentonHomeApp.makeApp()
            app.launchEnvironment["FENTON_GALLERY"] = page
            app.launchEnvironment["FENTON_APPEARANCE"] = appearance
            app.launchEnvironment.merge(environment) { _, new in new }
            app.launchArguments += arguments
            app.launch()
            let anchor = ready(app)
            XCTAssertTrue(anchor.waitForExistence(timeout: 30), "\(name) did not open")
            XCTAssertTrue(anchor.wait(for: \.isHittable, toEqual: true, timeout: 10), "\(name) is still presenting")
            sleep(1)
            keepScreenshot(app, "g4-\(name)-\(appearance)-\(layout)")
            app.terminate()
        }
    }

    func testGallerySheet() {
        for section in ["Controls", "Families", "Settings"] {
            capture("gallery-\(section.lowercased())", page: "direction-g",
                    arguments: ["-directionGSheet", "open", "-directionGSheetSection", section]) { self.element("g.sheet.tabs", in: $0) }
        }
    }

    func testSecuritySheet() {
        for appearance in ["light", "dark"] {
            let app = FentonHomeApp.makeApp()
            app.launchEnvironment["FENTON_GALLERY"] = "security"
            app.launchEnvironment["FENTON_APPEARANCE"] = appearance
            app.launch()
            XCTAssertTrue(app.buttons["security.chip.security"].waitForExistence(timeout: 30))
            app.buttons["security.chip.security"].tap()
            XCTAssertTrue(app.navigationBars["Security System"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
            sleep(1)
            keepScreenshot(app, "g4-security-\(appearance)-\(layout)")
            app.terminate()
        }
    }

    func testClimateSheet() {
        capture("climate-rooms", page: "climate", environment: ["FENTON_GALLERY_CLIMATE_OPEN": "rooms", "FENTON_GALLERY_CLEAN": "1"]) {
            $0.buttons["Close"]
        }
        capture("climate-room", page: "climate", environment: ["FENTON_GALLERY_CLIMATE_OPEN": "room:master_bedroom", "FENTON_GALLERY_CLEAN": "1"]) {
            $0.buttons["Close"]
        }
    }

    func testRemoteSheet() {
        capture("remote", page: "media-remote", environment: [
            "FENTON_GALLERY_REMOTE": "living-room-shield", "FENTON_GALLERY_TAB": "controls", "FENTON_GALLERY_OFFLINE": "1",
        ]) { self.element("remote.power", in: $0) }
    }

    func testPurifierAndBedSheets() {
        capture("purifier", page: "room-devices", environment: [
            "FENTON_GALLERY_DEVICE": "purifier-auto", "FENTON_GALLERY_TAB": "controls", "FENTON_GALLERY_CLEAN": "1",
        ]) { self.element("purifier.mode", in: $0) }
        capture("bed", page: "bedroom", environment: [
            "FENTON_GALLERY_SCENARIO": "default", "FENTON_GALLERY_SHEET": "stephens-bed", "FENTON_GALLERY_CLEAN": "1",
        ]) { self.element("bed.hint", in: $0) }
    }

    func testQuickLinksSheet() {
        capture("quick-links", page: "rooms", environment: [
            "FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_QUICK_LINKS": "1", "FENTON_GALLERY_CLEAN": "1",
        ]) { self.element("quickLinks.rooms", in: $0) }
    }

    func testVacuumSheet() {
        for tab in ["controls", "zones"] {
            capture("vacuum-\(tab)", page: "vacuums", environment: [
                "FENTON_GALLERY_VACUUM": "valetudo_exaltedsneakydeer", "FENTON_GALLERY_TAB": tab,
                "FENTON_GALLERY_SCENARIO": "docked", "FENTON_GALLERY_CLEAN": "1",
            ]) { self.element("vacuum.tabs", in: $0) }
        }
    }
}
