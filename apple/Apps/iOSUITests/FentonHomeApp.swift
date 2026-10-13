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
    ///   - readyIdentifier: What shows once signed in, when not Home (e.g. `inventory.pantry` with
    ///     `FENTON_OPEN_INVENTORY`, which pushes the page over Home).
    static func launchSignedIn(passwordOnly: Bool = false, arguments: [String] = [], environment extra: [String: String] = [:],
                               readyIdentifier: String? = nil) throws -> XCUIApplication {
        func ready(_ app: XCUIApplication) -> XCUIElement {
            readyIdentifier.map { app.descendants(matching: .any)[$0] } ?? app.buttons["home.chip.lights"]
        }
        let environment = ProcessInfo.processInfo.environment
        if !passwordOnly, let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let app = makeApp()
            app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
            app.launchEnvironment["FENTON_HASS_TOKEN"] = token
            app.launchArguments += arguments
            app.launchEnvironment.merge(extra) { _, new in new }
            if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
            app.launch()
            XCTAssertTrue(ready(app).waitForExistence(timeout: 30), "Home did not appear")
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
        XCTAssertTrue(app.textFields["login.username"].waitForExistence(timeout: 10), "Sign-in did not appear")
        // At AX5 on a short screen (the folded iPhone Duo) Sign In sits below the fold.
        // Drag in the form's leading gutter: a swipe that starts on the multi-line server field
        // scrolls the field's own text, not the form.
        let form = app.collectionViews.firstMatch
        for _ in 0..<6 where !(submit.exists && submit.isHittable) {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)))
        }
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "Sign In button not reachable")
        submit.tap()
        XCTAssertTrue(ready(app).waitForExistence(timeout: 30), "Home did not appear after sign-in")
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
        // Read once: per-issue queries add up, and many accessibility requests crash the iPad simulator's backboardd.
        let floatingBarTop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fab.'"))
            .allElementsBoundByIndex.map(\.frame.minY).min()
        // The audit can dismiss a popover while it runs, so note it before starting.
        let popover = app.otherElements["PopoverDismissRegion"].exists && app.popovers.firstMatch.exists
            ? app.popovers.firstMatch.frame : nil
        // The handler only collects: element queries made inside it count against the audit's own deadline, and on
        // a long scrolled list (iPhone vacuum Auto-Clean tab, 2026-10-12) they made it fail "to complete in time".
        // Contrast runs as its own pass: alongside the Dynamic Type or text-clipping checks its issues can lose their
        // element (probed 2026-10-11: a row half under the floating action bar came back unattributed), and an
        // unattributed issue cannot be measured or placed.
        var issues: [XCUIAccessibilityAuditIssue] = []
        try app.performAccessibilityAudit(for: .contrast) { issue in
            issues.append(issue)
            return true
        }
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            issues.append(issue)
            return true
        }
        // Page text under the floating action bar's hard scroll edge is faded out, and its contrast issue can come
        // back without an element (FloatingActions gallery, iPhone 2026-10-12). Like the tab bar rule, accept an
        // element-less contrast issue only while page text really sits under the bar. Read once, after the audit.
        let textUnderFloatingBar = floatingBarTop.map { top in
            app.staticTexts.allElementsBoundByIndex.contains { !$0.label.isEmpty && $0.frame.maxY > top && $0.frame.minY < top + 52 }
        } ?? false
        for issue in issues {
            if isSystemDrawn(issue, in: app, popover: popover) { continue }
            if issue.auditType == .contrast, issue.element == nil, textUnderFloatingBar { continue }
            var measured = ""
            if issue.auditType == .contrast, let element = issue.element, let capture,
               var ratio = RenderedContrast.ratio(of: element.frame, in: capture) {
                // The audit scrolls long sheets to inspect elements, so the frame it reports can belong to a later
                // scroll position than the opening capture (iPad vacuum sheet, 2026-10-12: visible 19:1 text measured
                // 1.2:1). Measure a low reading again against the screen as it is now.
                if ratio < 4.5, let now = RenderedContrast.Capture.screen(),
                   let fresh = RenderedContrast.ratio(of: element.frame, in: now) {
                    ratio = max(ratio, fresh)
                }
                // The audit misjudges text on materials (notably on iPad); accept it when it renders >= 4.5:1.
                if ratio >= 4.5 { continue }
                // Nothing drawn at an unreachable element: it is scrolled out of view (e.g. below an iPad
                // form sheet's edge), not low contrast.
                if ratio < 1.5, !element.isHittable { continue }
                // Nothing drawn under the floating action bar: its hard scroll edge covers rows that scroll
                // beneath it (inventory All Food, 2026-10-11), so the text is hidden, not low contrast.
                if ratio < 1.5, let floatingBarTop, element.frame.maxY > floatingBarTop { continue }
                measured = String(format: " (rendered %.1f:1)", ratio)
            }
            if ax5Page != nil, issue.auditType == .dynamicType,
               issue.compactDescription.localizedCaseInsensitiveContains("partially unsupported") {
                if let element = issue.element, !element.label.isEmpty {
                    unconfirmedType.append((element.label, element.frame.height))
                } else {
                    unattributedType += 1
                }
                continue
            }
            let element = issue.element
            open.append("\(issue.compactDescription): \(element?.elementType.rawValue ?? 0) '\(element?.label ?? "")'\(measured) "
                + issue.detailedDescription)
        }
        let auditedScreen = XCTAttachment(screenshot: app.screenshot())
        if let ax5Page, !unconfirmedType.isEmpty || unattributedType > 0 {
            // Only labels that name one content text on the page: bar titles are left out (they barely
            // scale and can repeat a section header, like the Home Assistant modal's), and comparing two
            // different texts proves nothing. Read from one snapshot per page: per-label queries ran
            // hundreds of accessibility requests and crashed the iPad simulator's backboardd.
            func uniqueTexts(in app: XCUIApplication) -> [String: CGRect] {
                guard let root = try? app.snapshot() else { return [:] }
                var bars: [CGRect] = []
                var texts: [(String, CGRect)] = []
                func walk(_ node: XCUIElementSnapshot) {
                    if node.elementType == .navigationBar { bars.append(node.frame) }
                    // Buttons too: a button's own label (Form rows, capsules) has no static text child to measure.
                    if node.elementType == .staticText || node.elementType == .button, !node.label.isEmpty {
                        texts.append((node.label, node.frame))
                    }
                    node.children.forEach(walk)
                }
                walk(root)
                let content = texts.filter { text in !bars.contains { $0.intersects(text.1) } }
                let counts = Dictionary(content.map { ($0.0, 1) }, uniquingKeysWith: +)
                return Dictionary(content.filter { counts[$0.0] == 1 }, uniquingKeysWith: { first, _ in first })
            }
            let before = uniqueTexts(in: app)
            let sample = app.staticTexts.allElementsBoundByIndex.prefix(12)
                .filter { before[$0.label] != nil && $0.isHittable }
                .map { ($0.label, $0.frame.height) }
            // Decided before the relaunch: `large` is the same app, so `app` then shows the AX5 page.
            let uniqueBefore = Set(sample.map(\.0) + unconfirmedType.map(\.label).filter { before[$0] != nil })
            let large = try ax5Page()
            // AX5 pushes rows below the fold (the folded iPhone Duo shows one or two), so scroll the
            // page to measure every text this audit needs.
            var largeHeights: [String: CGFloat] = [:]
            for _ in 0..<8 {
                for (label, frame) in uniqueTexts(in: large) where uniqueBefore.contains(label) && largeHeights[label] == nil {
                    largeHeights[label] = frame.height
                }
                let scroller = large.collectionViews.firstMatch.exists ? large.collectionViews.firstMatch : large.scrollViews.firstMatch
                guard largeHeights.count < uniqueBefore.count, scroller.exists else { break }
                scroller.swipeUp()
            }
            func grew(_ label: String, _ height: CGFloat) -> Bool? {
                largeHeights[label].map { $0 >= height * 1.35 }
            }
            // A live value (humidity, temperature) can change between launches; then the page decides:
            // the sampled texts together are 1.35x taller and none shrank. Measured together because a
            // grouped section header's frame carries fixed padding (Server: 40.3 → 52 pt at AX5 while
            // its glyphs triple), so it can miss 1.35x alone.
            let compared = sample.compactMap { label, height in largeHeights[label].map { (height, $0) } }
            let pageGrew = !compared.isEmpty && compared.allSatisfy { $0.1 >= $0.0 }
                && compared.map(\.1).reduce(0, +) >= 1.35 * compared.map(\.0).reduce(0, +)
            var missed = false
            for (label, height) in unconfirmedType where !(grew(label, height) ?? pageGrew) {
                let measured = largeHeights[label].map { String(format: " (%.1f → %.1f pt)", height, $0) } ?? ""
                open.append("Dynamic Type: '\(label)' did not grow 1.35x at AX5\(measured)")
                missed = true
            }
            if missed || (unattributedType > 0 && !pageGrew) {
                let evidence = XCTAttachment(screenshot: large.screenshot())
                evidence.name = "AX5 screen"
                evidence.lifetime = .keepAlways
                XCTContext.runActivity(named: "AX5 relaunch") { $0.add(evidence) }
            }
            if missed || unattributedType > 0, !pageGrew {
                let pairs = compared.map { String(format: "%.1f → %.1f", $0.0, $0.1) }.joined(separator: ", ")
                open.append("Page check (\(compared.count) of \(sample.count) sampled texts on the AX5 page): \(pairs)")
            }
            if unattributedType > 0, !pageGrew {
                open.append("Dynamic Type: \(unattributedType) issue(s) with no element, and the page did not grow 1.35x at AX5")
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

    private static func isSystemDrawn(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication, popover: CGRect?) -> Bool {
        guard let element = issue.element else {
            // Same for the content behind an action-sheet popover noted as the audit started (the
            // audit can dismiss it): the popover's dismiss region hides it from assistive technologies.
            if issue.auditType == .elementDetection, popover != nil { return true }
            // Text behind a modal sheet (iPad form sheets leave Home visible around them) is drawn but
            // hidden from assistive technologies by the modal. Accept it only while a sheet is up and
            // Home's own controls can't be reached (the sheet's dimming layer takes the touches).
            // A page pushed inside the sheet shows Back, not Done; the page behind still has its own bar, so two
            // navigation bars also mean a modal over a page (Bedroom editors on iPad, 2026-10-12).
            let modalUp = app.navigationBars.buttons["Done"].exists || app.navigationBars.count > 1
            if issue.auditType == .elementDetection, modalUp, !app.buttons["home.chip.lights"].isHittable {
                return true
            }
            // The same for an inventory page behind an iPad form sheet (Sort, Filter, Add Item, the editor;
            // Add Item's later steps show Back instead of Cancel): its dimmed text is sampled through the scrim, and
            // contrast issues there come back without an element (iPad, 2026-10-12).
            if issue.auditType == .elementDetection || issue.auditType == .contrast,
               app.navigationBars.buttons["Done"].exists || app.navigationBars.buttons["Cancel"].exists
                || app.buttons["scan.back"].exists,
               app.buttons["inventory.row.cart"].firstMatch.exists, !app.buttons["inventory.row.cart"].firstMatch.isHittable {
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
            // Text behind an action-sheet popover (iOS 27 sign-out confirmation) is sampled through
            // the popover's dismiss region; the popover's own buttons stay checked.
            if let popover, !popover.contains(element.frame) { return true }
            if isScrolledOutOfView(element, in: app) { return true }
            // A row scrolled under the glass tab bar is sampled against the bar (iPhone Settings'
            // last row, 2026-10-11: 1.2:1); the bar's own items stay checked.
            if isUnderTabBar(element, in: app) { return true }
            if element.elementType == .button && app.navigationBars.buttons[element.label].exists { return true }
            return element.elementType == .staticText && systemSectionHeaders.contains(element.label)
        case .dynamicType, .textClipped:
            // Toolbar buttons are system-drawn and offer the Large Content Viewer instead of scaling.
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
        let holder = NSPredicate(format: "label == %@", element.label)
        // Below the window's edge (a long sheet column in iPad landscape): the capture holds only part of it.
        let window = app.windows.firstMatch.frame
        if !window.isEmpty, !window.insetBy(dx: -1, dy: -1).contains(frame) { return true }
        // Scrolled under a navigation bar (wholly or partly): the bar's scroll-edge effect deliberately obscures it.
        // The bar's own title and buttons are its descendants and stay checked.
        for navigationBar in app.navigationBars.allElementsBoundByIndex {
            let bar = navigationBar.frame
            guard !bar.isEmpty, bar.intersects(frame), frame.minY < bar.maxY - 1 else { continue }
            if !navigationBar.descendants(matching: element.elementType).matching(holder).firstMatch.exists { return true }
        }
        // Only scroll views that hold this element (not, say, Home's behind a sheet).
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

    /// Whether a page element (not one of the tab bar's own items) overlaps the tab bar.
    private static func isUnderTabBar(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.exists, element.frame.intersects(bar.frame) else { return false }
        return !bar.descendants(matching: element.elementType)[element.label].exists
    }

    /// `Form` section headers, styled by the system.
    private static let systemSectionHeaders: Set<String> = [
        "Home Assistant", "Two-factor code",
        // Inventory sort sheet and Add Item (measured 3.3:1 on iPhone, 2026-10-11).
        "Sort By", "Sort Direction", "What item are you adding?", "How many are you adding?", "Where should it be stored?",
        "When does it expire?", "Quick Expiration Dates", "Prepared Food",
    ]
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
        // `simctl io` can take over 30 s on a loaded host; a short wait moved on and mislabeled the next capture.
        let deadline = Date().addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
