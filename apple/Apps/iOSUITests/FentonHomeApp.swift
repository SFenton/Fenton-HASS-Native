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

    /// A fresh app handle; forwards `FENTON_REDACT_PRIVATE` so shared screenshots hide private data.
    static func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        if let redact = ProcessInfo.processInfo.environment["FENTON_REDACT_PRIVATE"] {
            app.launchEnvironment["FENTON_REDACT_PRIVATE"] = redact
        }
        return app
    }

    /// Launches signed out.
    static func launchSignedOut() -> XCUIApplication {
        let app = makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launch()
        return app
    }

    /// Launches signed out, then signs in with the runner's credentials. Skips when none are provided.
    /// `TEST_RUNNER_FENTON_HASS_TOKEN` (a long-lived access token) takes precedence over the password.
    /// - Parameter passwordOnly: Ignore the token and go through the real login flow.
    ///   - arguments: Extra launch arguments (e.g. ``ax5``).
    ///   - environment: Extra launch environment (e.g. `FENTON_CAMERA_MODE`).
    static func launchSignedIn(passwordOnly: Bool = false, arguments: [String] = [], environment extra: [String: String] = [:]) throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        if !passwordOnly, let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let app = makeApp()
            app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
            app.launchEnvironment["FENTON_HASS_TOKEN"] = token
            app.launchArguments += arguments
            app.launchEnvironment.merge(extra) { _, new in new }
            if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
            app.launch()
            XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 30), "Home did not appear")
            return app
        }
        guard let credentials else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_USERNAME / _PASSWORD to run signed-in journeys")
        }
        let app = makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_USERNAME"] = credentials.username
        app.launchEnvironment["FENTON_HASS_PASSWORD"] = credentials.password
        app.launchArguments += arguments
        app.launchEnvironment.merge(extra) { _, new in new }
        if let server = credentials.server { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        submit.tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].waitForExistence(timeout: 30), "Home did not appear after sign-in")
        return app
    }

    /// Launches the debug component gallery on `page` (e.g. `thermostat-dial`): fixture data, no sign-in.
    static func launchGallery(_ page: String, arguments: [String] = []) -> XCUIApplication {
        let app = makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// Launch arguments for the largest accessibility text size (AX5).
    static let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Runs the full audit, accepting only issues on system-drawn elements the app does not style:
    /// the grouped `Form` section header's secondary text, toolbar bar buttons (e.g. a sheet's glass Done), and
    /// the system's dimmed style on disabled controls (exempt from WCAG 1.4.3).
    /// Collects every remaining issue so one run lists them all, then fails once with the list.
    ///
    /// "Dynamic Type font sizes are partially unsupported" is a known false positive on iPad (Festival's
    /// `dynamic-type-grows` waiver). With `ax5Page` (relaunches the same page at AX5) such an issue is
    /// accepted only when the same text is at least 1.35x taller there; an issue with no element only
    /// when every sampled text on the page grew that much.
    static func audit(
        _ app: XCUIApplication, ax5Page: (() throws -> XCUIApplication)? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        var open: [String] = []
        var unconfirmedType: [(label: String, height: CGFloat)] = []
        var unattributedType = 0
        let capture = RenderedContrast.Capture.screen()
        try app.performAccessibilityAudit(for: .all) { issue in
            if isSystemDrawn(issue, in: app) { return true }
            var measured = ""
            if issue.auditType == .contrast, let element = issue.element, let capture,
               let ratio = RenderedContrast.ratio(of: element.frame, in: capture) {
                // The audit misjudges text on materials (notably on iPad); accept it when it renders >= 4.5:1.
                if ratio >= 4.5 { return true }
                // Nothing drawn at an unreachable element: it is scrolled out of view (e.g. below an iPad
                // form sheet's edge), not low contrast.
                if ratio < 1.5, !element.isHittable { return true }
                measured = String(format: " (rendered %.1f:1)", ratio)
            }
            if ax5Page != nil, issue.auditType == .dynamicType,
               issue.compactDescription.localizedCaseInsensitiveContains("partially unsupported") {
                if let element = issue.element, !element.label.isEmpty {
                    unconfirmedType.append((element.label, element.frame.height))
                } else {
                    unattributedType += 1
                }
                return true
            }
            let element = issue.element
            open.append("\(issue.compactDescription): \(element?.elementType.rawValue ?? 0) '\(element?.label ?? "")'\(measured) "
                + issue.detailedDescription)
            return true
        }
        let auditedScreen = XCTAttachment(screenshot: app.screenshot())
        if let ax5Page, !unconfirmedType.isEmpty || unattributedType > 0 {
            // A label shown twice (a list row and the open detail's title) can't be paired across
            // launches, so only unique labels are samples.
            func isUnique(_ label: String, in page: XCUIApplication) -> Bool {
                page.staticTexts.matching(NSPredicate(format: "label == %@", label)).count == 1
            }
            let sample = app.staticTexts.allElementsBoundByIndex.prefix(12)
                .filter { !$0.label.isEmpty && $0.isHittable && isUnique($0.label, in: app) }
                .map { ($0.label, $0.frame.height) }
            let large = try ax5Page()
            func grew(_ label: String, _ height: CGFloat) -> Bool? {
                // Only an on-screen element is a measurement; a row scrolled out of the AX5 page is
                // unknown, so the page decides.
                let element = large.staticTexts[label].firstMatch
                guard element.exists, element.isHittable, isUnique(label, in: large) else { return nil }
                return element.frame.height >= height * 1.35
            }
            // A live value (humidity, temperature) can change between launches; then the page decides.
            let pageGrew = !sample.isEmpty && sample.allSatisfy { grew($0.0, $0.1) ?? true }
                && sample.contains { grew($0.0, $0.1) == true }
            // Name the page samples that held the page decision back, so a failure says why.
            let stuck = sample.filter { grew($0.0, $0.1) == false }
                .map { "'\($0.0)' \(Int($0.1))pt→\(Int(large.staticTexts[$0.0].firstMatch.frame.height))pt" }
            let why = stuck.isEmpty ? "" : " (page samples that did not grow: \(stuck.joined(separator: ", ")))"
            for (label, height) in unconfirmedType where !(grew(label, height) ?? pageGrew) {
                open.append("Dynamic Type: '\(label)' did not grow 1.35x at AX5" + (grew(label, height) == nil ? why : ""))
            }
            if unattributedType > 0, !pageGrew {
                open.append("Dynamic Type: \(unattributedType) issue(s) with no element, and the page did not grow 1.35x at AX5" + why)
            }
        }
        if !open.isEmpty {
            let screenshot = auditedScreen
            screenshot.name = "Audited screen"
            screenshot.lifetime = .keepAlways
            XCTContext.runActivity(named: "Accessibility audit") { $0.add(screenshot) }
            XCTFail("Accessibility audit:\n" + open.joined(separator: "\n"), file: file, line: line)
        }
    }

    private static func isSystemDrawn(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard let element = issue.element else {
            // Text behind a modal sheet (iPad form sheets leave Home visible around them) is drawn but
            // hidden from assistive technologies by the modal. Accept it only while a sheet is up and
            // Home's own controls can't be reached (the sheet's dimming layer takes the touches).
            if issue.auditType == .elementDetection, app.navigationBars.buttons["Done"].exists,
               !app.buttons["home.chip.lights"].isHittable {
                return true
            }
            // The same for the navigation flyout: the page under its scrim is drawn but hidden from
            // assistive technologies while it is open. Accept it only while the flyout is up and Home's
            // controls are out of the accessibility tree.
            if issue.auditType == .elementDetection, app.descendants(matching: .any)["nav.flyout"].exists,
               !app.buttons["home.chip.lights"].exists {
                return true
            }
            // A list row scrolled under the glass tab bar is sampled against the bar and sometimes
            // loses its element (iPhone Settings, 2026-10-11: the "Home Assistant" header). Accept an
            // element-less contrast issue only while some page text really sits under the tab bar.
            if issue.auditType == .contrast, isPageTextUnderTabBar(in: app) {
                return true
            }
            // When contrast runs with the Dynamic Type or text-clipping checks, the disabled Sign In
            // button's issue loses its element (probed 2026-10-10: the same audit otherwise reports it
            // on that button). Accept it only while that button is on screen and disabled.
            let submit = app.buttons["login.submit"]
            return issue.auditType == .contrast && submit.exists && !submit.isEnabled
        }
        switch issue.auditType {
        case .contrast:
            if element.elementType == .button && !element.isEnabled { return true }
            if isScrolledOutOfView(element, in: app) { return true }
            if element.elementType == .button && app.navigationBars.buttons[element.label].exists { return true }
            return element.elementType == .staticText && systemSectionHeaders.contains(element.label)
        case .dynamicType:
            return element.elementType == .button && app.navigationBars.buttons[element.label].exists
        default:
            return false
        }
    }

    /// Text scrolled (partly) out of its scroll view is sampled against whatever covers it there, such as
    /// the folded iPhone Duo's toolbar rail or the screen edge under a sheet. It is out of view, not low
    /// contrast: accept it only when no scroll view's visible frame fully contains the element.
    private static func isScrolledOutOfView(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        // Below the window's edge (a long sheet column in iPad landscape): the capture holds only part of it.
        let window = app.windows.firstMatch.frame
        if !window.isEmpty, !window.insetBy(dx: -1, dy: -1).contains(frame) { return true }
        // Only scroll views that hold this element (not, say, Home's behind a sheet).
        let holder = NSPredicate(format: "label == %@", element.label)
        let scrollViews = app.scrollViews.allElementsBoundByIndex
            .filter { $0.frame.intersects(frame) && $0.descendants(matching: element.elementType).matching(holder)
                .allElementsBoundByIndex.contains { $0.frame == frame } }
            .map(\.frame)
        return !scrollViews.isEmpty && !scrollViews.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) }
    }

    /// Whether a page text (not the tab bar's own labels) overlaps the tab bar, i.e. is scrolled under it.
    private static func isPageTextUnderTabBar(in app: XCUIApplication) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.exists else { return false }
        let barFrame = bar.frame
        return app.staticTexts.allElementsBoundByIndex.contains { text in
            !text.label.isEmpty && text.frame.intersects(barFrame) && !bar.staticTexts[text.label].exists
        }
    }

    /// `Form` section headers, styled by the system.
    private static let systemSectionHeaders: Set<String> = ["Home Assistant", "Two-factor code"]
}

// MARK: - Screenshots

extension XCTestCase {
    /// Keeps a screenshot named `name` in the result bundle for design review.
    ///
    /// XCUIScreen captures only the outer panel, which is dark on an unfolded iPhone Duo. With
    /// `FENTON_CAPTURE_DIR` set, the host captures the lit panel: `<name>.ready` asks, `<name>.done` answers.
    @MainActor
    func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
