import XCTest

/// Launch helpers shared by every journey.
///
/// Credentials come only from the test runner's environment (`TEST_RUNNER_FENTON_HASS_USERNAME`,
/// `TEST_RUNNER_FENTON_HASS_PASSWORD`, optional `TEST_RUNNER_FENTON_HASS_SERVER`), set on the Mac from
/// the project's local temp.env. They are never committed or logged.
enum FentonHomeApp {
    /// Which device family the run is on, from the simulator's own name (never hard-coded per test).
    enum Family { case iPhone, iPhoneDuo, iPad }

    static var family: Family {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        if name.localizedCaseInsensitiveContains("Duo") { return .iPhoneDuo }
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }

    static var credentials: (username: String, password: String, server: String?)? {
        let environment = ProcessInfo.processInfo.environment
        guard let username = environment["FENTON_HASS_USERNAME"], !username.isEmpty,
              let password = environment["FENTON_HASS_PASSWORD"], !password.isEmpty else { return nil }
        return (username, password, environment["FENTON_HASS_SERVER"])
    }

    /// Launches signed out.
    static func launchSignedOut() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launch()
        return app
    }

    /// Launches signed out, then signs in with the runner's credentials. Skips when none are provided.
    static func launchSignedIn() throws -> XCUIApplication {
        guard let credentials else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_USERNAME / _PASSWORD to run signed-in journeys")
        }
        let app = XCUIApplication()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_USERNAME"] = credentials.username
        app.launchEnvironment["FENTON_HASS_PASSWORD"] = credentials.password
        if let server = credentials.server { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        submit.tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 30), "Home did not appear after sign-in")
        return app
    }
}
