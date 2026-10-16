import XCTest

/// The full-app accessibility sweep (direction G, Phase 4): every tab root, Quick Links, Account, a room page and
/// the main sheets, signed in against the house, each through `FentonHomeApp.audit` (contrast, text clipping and
/// the AX5 relaunch). Tab roots also check VoiceOver's reading order, and run again under Reduce Motion, Reduce
/// Transparency, Increase Contrast and Bold Text together.
///
/// One test per page, so `-only-testing` can run a page alone and a simulator crash under host load costs one
/// rerun (devices.md). Nothing here changes a device: every step opens a page or sheet and reads it.
/// Skips without credentials; the tests that run on the unfolded Duo do not skip after launch.
@MainActor
final class AccessibilitySweepJourneyTests: JourneyTestCase {
    typealias Setting = FentonHomeApp.SystemSetting

    /// Settings the running test turned on; the simulator keeps them until the next launch states them again.
    nonisolated(unsafe) private static var usedSettings = false

    override func tearDown() {
        super.tearDown()
        MainActor.assumeIsolated {
            // Leave the simulator as found: the settings belong to the device, not the app.
            if Self.usedSettings { FentonHomeApp.launchGallery("system-accessibility").terminate() }
        }
    }

    // MARK: - Sweep

    /// Opens a page, checks its reading order when it is a tab root, and audits it with the AX5 relaunch.
    /// - Parameters:
    ///   - name: The page, for screenshot names.
    ///   - settings: System settings to run under.
    ///   - rootTitle: A tab root's navigation title, which turns on the reading-order check.
    ///   - open: Navigates from a fresh signed-in launch to the page.
    private func sweep(_ name: String, settings: [Setting] = [], rootTitle: String? = nil,
                       open: @escaping (XCUIApplication) throws -> Void) throws {
        Self.usedSettings = !settings.isEmpty
        let environment = Setting.environment(settings)
        let app = try FentonHomeApp.launchSignedIn(environment: environment)
        try open(app)
        sleep(1) // Mid-animation frames fail contrast and clipping.
        if let rootTitle { try assertReadingOrder(app, title: rootTitle) }
        keepScreenshot(app, "sweep-\(name)-\(layout)")
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5, environment: environment)
            try open(large)
            sleep(1)
            return large
        }
    }

    // MARK: - Navigation steps

    private func root(_ section: String, _ title: String, in app: XCUIApplication) {
        if section != "home" { openSection(section, title: title, in: app) }
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15), "\(title) did not appear")
    }

    private func openQuickLinks(in app: XCUIApplication) {
        openSection("quickLinks", title: "Quick Links", in: app)
        XCTAssertTrue(element("quickLinks.rooms", in: app).waitForExistence(timeout: 10), "Quick Links did not open")
    }

    /// Scrolls the page in short drags until `target` can be tapped.
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !(target.exists && target.isHittable) {
            let above = target.exists && target.frame.midY < window.midY && target.frame.maxY > 0
            var x = window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(target.exists && target.isHittable, "\(target) never came into view", file: file, line: line)
    }

    private func tap(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(id) missing")
        reveal(target, in: app)
        target.tap()
    }

    /// Waits for a sheet to finish presenting: its Close button reachable.
    private func waitForSheet(in app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Sheet did not open")
        XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 10), "Sheet still presenting")
    }

    /// Quick Links, then a tile that pushes a page (Food, Vacuums, Media).
    private func openQuickLinkPage(_ id: String, in app: XCUIApplication) {
        openQuickLinks(in: app)
        tap("quickLinks.\(id)", in: app)
    }

    /// The Master Bedroom's page through Quick Links, Rooms.
    private func openMasterBedroom(in app: XCUIApplication) {
        openQuickLinks(in: app)
        tap("quickLinks.rooms", in: app)
        tap("rooms.master-bedroom", in: app)
        XCTAssertTrue(element("room.scroll.master-bedroom", in: app).waitForExistence(timeout: 15), "Master Bedroom did not open")
    }

    // MARK: - Tab roots

    func testHomeRoot() throws { try sweep("home", rootTitle: "Home") { self.root("home", "Home", in: $0) } }
    func testSecurityRoot() throws { try sweep("security", rootTitle: "Security") { self.root("security", "Security", in: $0) } }
    func testClimateRoot() throws { try sweep("climate", rootTitle: "Climate") { self.root("climate", "Climate", in: $0) } }
    func testChoresRoot() throws { try sweep("chores", rootTitle: "Chores") { self.root("chores", "Chores", in: $0) } }

    // MARK: - Tab roots under system accessibility settings

    func testHomeRootUnderSystemSettings() throws {
        try sweep("home-settings", settings: Setting.allCases, rootTitle: "Home") { self.root("home", "Home", in: $0) }
    }
    func testSecurityRootUnderSystemSettings() throws {
        try sweep("security-settings", settings: Setting.allCases, rootTitle: "Security") { self.root("security", "Security", in: $0) }
    }
    func testClimateRootUnderSystemSettings() throws {
        try sweep("climate-settings", settings: Setting.allCases, rootTitle: "Climate") { self.root("climate", "Climate", in: $0) }
    }
    func testChoresRootUnderSystemSettings() throws {
        try sweep("chores-settings", settings: Setting.allCases, rootTitle: "Chores") { self.root("chores", "Chores", in: $0) }
    }

    // MARK: - Sheets and pages

    func testQuickLinks() throws { try sweep("quick-links") { self.openQuickLinks(in: $0) } }

    func testAccount() throws {
        try sweep("account") { $0.openAccountSheet() }
    }

    func testRoomPage() throws { try sweep("room") { self.openMasterBedroom(in: $0) } }

    func testHomeChipSheet() throws {
        try sweep("home-chip-sheet") {
            $0.buttons["home.chip.lights"].tap()
            self.waitForSheet(in: $0)
        }
    }

    func testClimateAdvancedControls() throws {
        try sweep("climate-advanced") {
            self.root("climate", "Climate", in: $0)
            self.tap("climate.entry.automation", in: $0)
            self.waitForSheet(in: $0)
        }
    }

    func testSecuritySystemSheet() throws {
        try sweep("security-system") {
            self.root("security", "Security", in: $0)
            self.tap("security.chip.security", in: $0)
            XCTAssertTrue($0.navigationBars["Security System"].waitForExistence(timeout: 10), "Security system sheet did not open")
            self.waitForSheet(in: $0)
        }
    }

    func testMediaRemote() throws {
        try sweep("media-remote") {
            self.openQuickLinkPage("media", in: $0)
            XCTAssertTrue(self.element("media.scroll", in: $0).waitForExistence(timeout: 15), "Media did not open")
            let card = $0.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'media.card.'")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15), "Media has no device cards")
            self.reveal(card, in: $0)
            card.tap()
            self.waitForSheet(in: $0)
        }
    }

    func testRoomDeviceSheet() throws {
        try sweep("room-device") {
            self.openMasterBedroom(in: $0)
            self.tap("room.card.Humidifier", in: $0)
            self.waitForSheet(in: $0)
        }
    }

    func testBedSheet() throws {
        try sweep("bed") {
            self.openMasterBedroom(in: $0)
            self.tap("room.card.Stephen's Bed", in: $0)
            XCTAssertTrue(self.element("bed.dial", in: $0).waitForExistence(timeout: 15), "Bed sheet did not open")
            self.waitForSheet(in: $0)
        }
    }

    func testFoodHub() throws {
        try sweep("food") {
            self.openQuickLinkPage("food", in: $0)
            XCTAssertTrue(self.element("food.scroll", in: $0).waitForExistence(timeout: 15), "Food did not open")
        }
    }

    func testVacuums() throws {
        try sweep("vacuums") {
            self.openQuickLinkPage("vacuums", in: $0)
            XCTAssertTrue($0.navigationBars["Vacuums"].waitForExistence(timeout: 15), "Vacuums did not open")
        }
    }

    // MARK: - Reading order

    /// How far (pt) back up the page a stop may jump before the order counts as wrong: wider than a component's
    /// own two lines (a label and its value), narrower than a section.
    private static let rowTolerance: CGFloat = 40

    /// One element VoiceOver can land on, in the order it visits them.
    struct Stop: CustomStringConvertible {
        var label: String
        var type: XCUIElement.ElementType
        var frame: CGRect
        var description: String { "\(type.rawValue) '\(label)' y\(Int(frame.minY)) x\(Int(frame.minX)) \(Int(frame.width))x\(Int(frame.height))" }
    }

    /// The accessibility stops on screen in document order (the order SwiftUI exposes and VoiceOver swipes through).
    /// Controls are one stop each; the tab bar and the folded Duo's rail are left out.
    func readingOrder(of app: XCUIApplication) throws -> [Stop] {
        let root = try app.snapshot()
        let window = app.windows.firstMatch.frame
        let controls: Set<XCUIElement.ElementType> = [.button, .switch, .slider, .textField, .secureTextField, .link, .toggle, .segmentedControl]
        var stops: [Stop] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .tabBar { return }
            let isControl = controls.contains(node.elementType)
            if (node.elementType == .staticText || isControl), !node.label.isEmpty,
               !node.frame.isEmpty, window.intersects(node.frame), window.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)) {
                stops.append(Stop(label: node.label, type: node.elementType, frame: node.frame))
            }
            if isControl { return }
            node.children.forEach(walk)
        }
        walk(root)
        return stops
    }

    /// The page title comes before the page's content, and the content follows in visual order: down the page, and
    /// left to right along a row. Navigation bar buttons may come before or after the title.
    func assertReadingOrder(_ app: XCUIApplication, title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let stops = try readingOrder(of: app)
        let listing = stops.map(\.description).joined(separator: "\n")
        XCTContext.runActivity(named: "Reading order of \(title)") { activity in
            let attachment = XCTAttachment(string: listing)
            attachment.name = "reading-order-\(title)"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        let bar = app.navigationBars[title].frame
        func inBar(_ stop: Stop) -> Bool { !bar.isEmpty && bar.contains(CGPoint(x: stop.frame.midX, y: stop.frame.midY)) }
        guard let titleIndex = stops.firstIndex(where: { $0.type == .staticText && $0.label == title }) else {
            XCTFail("No '\(title)' title stop in the reading order:\n\(listing)", file: file, line: line)
            return
        }
        let before = stops[..<titleIndex].filter { !inBar($0) }
        XCTAssertTrue(before.isEmpty, "Content comes before the '\(title)' title:\n\(listing)", file: file, line: line)
        let content = stops[(titleIndex + 1)...].filter { !inBar($0) }
        var violations: [String] = []
        for (a, b) in zip(content, content.dropFirst()) {
            // A stop inside the previous one is part of the same component (a card's own texts).
            if a.frame.insetBy(dx: -1, dy: -1).contains(b.frame) { continue }
            let sameRow = abs(a.frame.midY - b.frame.midY) < min(a.frame.height, b.frame.height) / 2
            if sameRow {
                if b.frame.minX < a.frame.minX - 4 { violations.append("\(b) reads after \(a), which is to its right") }
            } else if b.frame.maxY < a.frame.minY - Self.rowTolerance {
                // Only a clear jump back up the page counts: a component may read a label then its value across
                // two short lines (an hour, then its temperature) and then continue in the next column.
                violations.append("\(b) reads after \(a), which is well below it")
            }
        }
        XCTAssertTrue(violations.isEmpty, "Reading order is not top to bottom, leading to trailing:\n"
            + violations.joined(separator: "\n") + "\n--- order ---\n" + listing, file: file, line: line)
    }
}
