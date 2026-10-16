import XCTest

/// Proves the journeys' launch options for system accessibility settings take effect, using the gallery page that
/// reports what the app sees (`FENTON_GALLERY=system-accessibility`). The sweep journeys rely on these.
@MainActor
final class SystemSettingsJourneyTests: JourneyTestCase {
    private func reading(_ setting: FentonHomeApp.SystemSetting, in app: XCUIApplication) -> String {
        element("env.\(setting.rawValue)", in: app).label
    }

    /// The settings belong to the simulator: leave it as found.
    override func tearDown() {
        super.tearDown()
        MainActor.assumeIsolated { FentonHomeApp.launchGallery("system-accessibility").terminate() }
    }

    func testLaunchOptionsTakeEffect() {
        continueAfterFailure = true
        let off = FentonHomeApp.launchGallery("system-accessibility")
        XCTAssertTrue(element("env.reduceMotion", in: off).waitForExistence(timeout: 15))
        for setting in FentonHomeApp.SystemSetting.allCases {
            XCTAssertEqual(reading(setting, in: off), "\(setting.rawValue): off", "\(setting) should default to off")
        }
        off.terminate()
        for setting in FentonHomeApp.SystemSetting.allCases {
            let app = FentonHomeApp.launchGallery("system-accessibility", environment: FentonHomeApp.SystemSetting.environment([setting]))
            XCTAssertTrue(element("env.reduceMotion", in: app).waitForExistence(timeout: 15))
            for other in FentonHomeApp.SystemSetting.allCases {
                XCTAssertEqual(reading(other, in: app), "\(other.rawValue): \(other == setting ? "on" : "off")",
                               "Launching with \(setting) should turn on only \(setting)")
            }
            app.terminate()
        }
    }
}
