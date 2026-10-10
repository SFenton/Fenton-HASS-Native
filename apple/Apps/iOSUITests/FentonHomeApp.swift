import XCTest

/// Launch helpers shared by every journey.
///
/// Credentials come only from the test runner's environment (`TEST_RUNNER_FENTON_HASS_USERNAME`,
/// `TEST_RUNNER_FENTON_HASS_PASSWORD` or `TEST_RUNNER_FENTON_HASS_TOKEN`, optional
/// `TEST_RUNNER_FENTON_HASS_SERVER`), set on the Mac from the project's local temp.env. They are never committed or logged.
@MainActor
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
    /// `TEST_RUNNER_FENTON_HASS_TOKEN` (a long-lived access token) takes precedence over the password.
    /// - Parameter passwordOnly: Ignore the token and go through the real login flow.
    static func launchSignedIn(passwordOnly: Bool = false) throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        if !passwordOnly, let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let app = XCUIApplication()
            app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
            app.launchEnvironment["FENTON_HASS_TOKEN"] = token
            if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
            app.launch()
            XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 30), "Home did not appear")
            return app
        }
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

    /// Runs the full audit, accepting only issues on system-drawn elements the app does not style:
    /// the grouped `Form` section header's secondary text, toolbar bar buttons (e.g. a sheet's glass Done), and
    /// the system's dimmed style on disabled controls (exempt from WCAG 1.4.3).
    /// Collects every remaining issue so one run lists them all, then fails once with the list.
    static func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        var open: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            if isSystemDrawn(issue, in: app) { return true }
            let element = issue.element
            open.append("\(issue.compactDescription): \(element?.elementType.rawValue ?? 0) '\(element?.label ?? "")' "
                + issue.detailedDescription)
            return true
        }
        if !open.isEmpty {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Audited screen"
            screenshot.lifetime = .keepAlways
            XCTContext.runActivity(named: "Accessibility audit") { $0.add(screenshot) }
            XCTFail("Accessibility audit:\n" + open.joined(separator: "\n"), file: file, line: line)
        }
    }

    private static func isSystemDrawn(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard let element = issue.element else { return false }
        switch issue.auditType {
        case .contrast:
            if element.elementType == .button && !element.isEnabled { return true }
            if element.elementType == .button && app.navigationBars.buttons[element.label].exists { return true }
            return element.elementType == .staticText && systemSectionHeaders.contains(element.label)
        case .dynamicType:
            return element.elementType == .button && app.navigationBars.buttons[element.label].exists
        default:
            return false
        }
    }

    /// `Form` section headers, styled by the system.
    private static let systemSectionHeaders: Set<String> = ["Home Assistant", "Two-factor code"]
}
