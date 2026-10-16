import XCTest

/// Sheets follow the system appearance while pages stay dark (`.agents/design/direction-g.md`, Layers: Sheets; plan
/// decision 6). Each journey launches with `FENTON_APPEARANCE=light` (the real system path has its own test), checks
/// by pixel that the sheet is light and the page behind stays dark, and runs the accessibility audit (contrast, Dynamic
/// Type at AX5, targets) on the sheet in light, on iPhone, iPhone Duo (folded) and iPad. The dark passes of the same
/// sheets are the feature journeys; `tools/ios_uitest.sh --appearance light` runs those in light too.
@MainActor
final class LightSheetsJourneyTests: JourneyTestCase {
    // MARK: - Launching

    /// A gallery page with the sheets pinned to `appearance` (nil leaves it to the simulator and the runner).
    private func gallery(_ page: String, environment: [String: String] = [:], arguments: [String] = [],
                         appearance: String? = "light") -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        if let appearance { app.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// Waits for `id` to be on screen and hittable, then lets the presentation settle (mid-animation frames fail
    /// contrast and clipping).
    private func waitReady(_ id: String, in app: XCUIApplication, what: String) {
        let ready = element(id, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "\(what) did not open")
        XCTAssertTrue(ready.wait(for: \.isHittable, toEqual: true, timeout: 10), "\(what) is still presenting")
        sleep(1)
    }

    // MARK: - Pixels

    /// Luminance samples along the strip just under the sheet's header, left of the Close button: the sheet's own
    /// ground (or a cell), never a title or a control.
    private func sheetSamples(_ app: XCUIApplication) -> [Double] {
        guard let capture = RenderedContrast.Capture.screen() else { return [] }
        let close = app.buttons["Close"].firstMatch.frame
        let y = close.maxY + 6
        return stride(from: close.minX - 24, to: close.minX - 224, by: -25).compactMap {
            RenderedContrast.luminance(at: CGPoint(x: $0, y: y), in: capture)
        }
    }

    private func assertSheet(_ app: XCUIApplication, isLight: Bool, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        let samples = sheetSamples(app)
        XCTAssertFalse(samples.isEmpty, "No pixels sampled \(message)", file: file, line: line)
        let matching = samples.filter { isLight ? $0 > 0.7 : $0 < 0.2 }
        XCTAssertGreaterThanOrEqual(matching.count * 2, samples.count,
                                    "\(message) sheet should be \(isLight ? "light" : "dark"); luminance \(samples)",
                                    file: file, line: line)
    }

    /// The wallpaper at the window's left edge, where no page content sits: dark under G's scrim.
    private func assertPageIsDark(_ app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let capture = RenderedContrast.Capture.screen() else { return XCTFail("No capture", file: file, line: line) }
        let window = app.windows.firstMatch.frame
        let samples = [0.35, 0.5, 0.65].compactMap {
            RenderedContrast.luminance(at: CGPoint(x: 3, y: window.height * $0), in: capture)
        }
        XCTAssertTrue(samples.allSatisfy { $0 < 0.3 }, "\(message): the page behind should stay dark; luminance \(samples)",
                      file: file, line: line)
    }

    // MARK: - Audit

    /// Opens the sheet through `launch` (called again with AX5 for the Dynamic Type check), asserts it is light, keeps
    /// a screenshot and audits it.
    private func auditLight(_ name: String, launch: @escaping ([String]) -> XCUIApplication) throws {
        let app = launch([])
        assertSheet(app, isLight: true, name)
        keepScreenshot(app, "light-\(name)-\(layout)")
        try FentonHomeApp.audit(app) { launch(FentonHomeApp.ax5) }
    }

    // MARK: - The split

    private func openGallerySheet(_ app: XCUIApplication) {
        let primary = app.buttons["g.primary"]
        for _ in 0..<6 where !primary.isHittable { app.swipeUp() }
        primary.tap()
        XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 5))
        sleep(1)
    }

    /// The sheet is light while the pages behind it are dark, and they are still dark once it closes.
    func testSheetIsLightWhileThePageStaysDark() {
        let app = gallery("direction-g")
        XCTAssertTrue(app.buttons["g.chip.Lights"].waitForExistence(timeout: 10))
        assertPageIsDark(app, "before the sheet")
        openGallerySheet(app)
        assertSheet(app, isLight: true, "gallery")
        keepScreenshot(app, "light-sheet-open-\(layout)")
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(app.buttons["g.primary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sheet.close"].waitForNonExistence(timeout: 5))
        sleep(1)
        assertPageIsDark(app, "after the sheet closed")
    }

    /// A system-appearance launch with no override: the probe says what the app measured.
    private func launchFollowingTheSystem() -> (app: XCUIApplication, probe: XCUIElement) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment.removeValue(forKey: "FENTON_APPEARANCE")
        app.launchEnvironment["FENTON_GALLERY"] = "direction-g"
        app.launchEnvironment["FENTON_APPEARANCE_DEBUG"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["g.chip.Lights"].waitForExistence(timeout: 10))
        let probe = element("appearance.probe", in: app)
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "No appearance probe")
        return (app, probe)
    }

    /// With no override at all, a light system draws light sheets over dark pages, and a dark one dark sheets.
    func testSystemAppearanceAloneDrivesTheSheets() {
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original }
        for (appearance, isLight) in [(XCUIDevice.Appearance.light, true), (.dark, false)] {
            XCUIDevice.shared.appearance = appearance
            let (app, probe) = launchFollowingTheSystem()
            assertPageIsDark(app, "system \(appearance == .light ? "light" : "dark")")
            openGallerySheet(app)
            assertSheet(app, isLight: isLight, "system \(isLight ? "light" : "dark") (\(probe.label))")
            if isLight { keepScreenshot(app, "light-system-appearance-\(layout)") }
            app.terminate()
        }
    }

    /// The user changes the appearance while the app runs (Control Center): the next sheet follows, the pages stay dark.
    func testSystemAppearanceChangeReachesARunningApp() {
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original }
        XCUIDevice.shared.appearance = .dark
        let (app, probe) = launchFollowingTheSystem()
        XCUIDevice.shared.appearance = .light
        sleep(2)
        assertPageIsDark(app, "after the system turned light")
        openGallerySheet(app)
        assertSheet(app, isLight: true, "after the change (\(probe.label))")
    }

    /// A pinned dark appearance keeps the sheet dark, whatever the simulator shows.
    func testPinnedDarkKeepsTheSheetDark() {
        let app = gallery("direction-g", appearance: "dark")
        XCTAssertTrue(app.buttons["g.chip.Lights"].waitForExistence(timeout: 10))
        openGallerySheet(app)
        assertSheet(app, isLight: false, "pinned dark")
    }

    // MARK: - Direction G gallery sheet

    /// Every section of the gallery sheet in light: filled, off, lit, error, tinted and washed tiles; every family off;
    /// the app tile; an inset list.
    func testGallerySheetSectionsPassAudit() throws {
        for section in ["Controls", "Families", "Apps", "Settings"] {
            try auditLight("gallery-\(section.lowercased())") { arguments in
                let app = self.gallery("direction-g", arguments: ["-directionGSheet", "open", "-directionGSheetSection", section] + arguments)
                self.waitReady("g.sheet.tabs", in: app, what: "gallery sheet")
                return app
            }
        }
    }

    // MARK: - Feature sheets

    func testSecuritySystemSheetPassesAuditInLight() throws {
        try auditLight("security-system") { arguments in
            let app = self.gallery("security", arguments: arguments)
            XCTAssertTrue(app.buttons["security.chip.security"].waitForExistence(timeout: 30), "Security page did not appear")
            app.buttons["security.chip.security"].tap()
            XCTAssertTrue(app.navigationBars["Security System"].waitForExistence(timeout: 10), "Security system sheet did not open")
            XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
            sleep(1)
            return app
        }
    }

    func testTriggeredSecuritySheetPassesAuditInLight() throws {
        try auditLight("security-triggered") { arguments in
            let app = self.gallery("security", environment: ["FENTON_GALLERY_SCENARIO": "triggered"], arguments: arguments)
            XCTAssertTrue(app.buttons["security.chip.security"].waitForExistence(timeout: 30), "Security page did not appear")
            app.buttons["security.chip.security"].tap()
            XCTAssertTrue(app.navigationBars["Security System"].waitForExistence(timeout: 10), "Security system sheet did not open")
            XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
            sleep(1)
            return app
        }
    }

    /// Thermostat · Advanced Controls: the rooms list, the automation form and a room's dial.
    func testClimateSheetPassesAuditInLight() throws {
        for open in ["rooms", "automation", "room:master_bedroom"] {
            try auditLight("climate-\(open.replacingOccurrences(of: ":", with: "-"))") { arguments in
                let app = self.gallery("climate", environment: ["FENTON_GALLERY_CLIMATE_OPEN": open, "FENTON_GALLERY_CLEAN": "1"],
                                       arguments: arguments)
                XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "Climate sheet did not open")
                sleep(1)
                return app
            }
        }
    }

    /// The media remote: the keys, the apps grid and the devices list.
    func testMediaRemotePassesAuditInLight() throws {
        for (remote, tab, ready) in [("living-room-shield", "controls", "remote.power"), ("living-room-shield", "apps", "remote.app.Plex"),
                                     ("theater-room-shield", "devices", "remote.device.Projector")] {
            try auditLight("remote-\(tab)") { arguments in
                let app = self.gallery("media-remote", environment: [
                    "FENTON_GALLERY_REMOTE": remote, "FENTON_GALLERY_TAB": tab, "FENTON_GALLERY_OFFLINE": "1",
                ], arguments: arguments)
                self.waitReady(ready, in: app, what: "remote sheet")
                return app
            }
        }
    }

    /// A room device sheet: the air purifier, and the humidifier's dial.
    func testRoomDeviceSheetsPassAuditInLight() throws {
        for (device, ready) in [("purifier-auto", "purifier.mode"), ("humidifier", "humidifier.power"), ("grill", "grill.header")] {
            try auditLight("device-\(device)") { arguments in
                let app = self.gallery("room-devices", environment: [
                    "FENTON_GALLERY_DEVICE": device, "FENTON_GALLERY_TAB": "controls", "FENTON_GALLERY_CLEAN": "1",
                ], arguments: arguments)
                self.waitReady(ready, in: app, what: "\(device) sheet")
                return app
            }
        }
    }

    /// The bed sheet (Stephen's side, with its dial and Special Modes).
    func testBedSheetPassesAuditInLight() throws {
        for tab in ["controls", "special-modes"] {
            try auditLight("bed-\(tab)") { arguments in
                let app = self.gallery("bedroom", environment: [
                    "FENTON_GALLERY_SCENARIO": "default", "FENTON_GALLERY_SHEET": "stephens-bed", "FENTON_GALLERY_TAB": tab,
                    "FENTON_GALLERY_CLEAN": "1",
                ], arguments: arguments)
                self.waitReady("bed.hint", in: app, what: "bed sheet")
                return app
            }
        }
    }

    /// Quick Links: the room grid tiles in a sheet.
    func testQuickLinksPassesAuditInLight() throws {
        try auditLight("quick-links") { arguments in
            let app = self.gallery("rooms", environment: [
                "FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_QUICK_LINKS": "1", "FENTON_GALLERY_CLEAN": "1",
            ], arguments: arguments)
            self.waitReady("quickLinks.rooms", in: app, what: "Quick Links")
            return app
        }
    }

    // MARK: - Sheets that stay dark

    /// The Weather sheet draws over its condition gradient and stays dark in the light appearance.
    func testWeatherSheetStaysDarkInLight() {
        let app = gallery("weather", environment: ["FENTON_GALLERY_WEATHER_OPEN": "1"])
        waitReady("weather.sheet", in: app, what: "Weather sheet")
        guard let capture = RenderedContrast.Capture.screen() else { return XCTFail("No capture") }
        let window = app.windows.firstMatch.frame
        let samples = [0.3, 0.45, 0.6].compactMap {
            RenderedContrast.luminance(at: CGPoint(x: window.midX, y: window.height * $0), in: capture)
        }
        keepScreenshot(app, "light-weather-stays-dark-\(layout)")
        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.allSatisfy { $0 < 0.5 }, "The Weather sheet must stay dark; luminance \(samples)")
    }

    // MARK: - Signed in

    /// Home's Lights chip sheet (the room overview: rows, a light tile slab and a group), in light.
    func testLightsOverviewSheetPassesAuditInLight() throws {
        func open(_ arguments: [String]) throws -> XCUIApplication {
            let app = try FentonHomeApp.launchSignedIn(arguments: arguments, environment: ["FENTON_APPEARANCE": "light"])
            app.buttons["home.chip.lights"].tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
            sleep(1)
            return app
        }
        let app = try open([])
        assertSheet(app, isLight: true, "lights overview")
        keepScreenshot(app, "light-lights-overview-\(layout)")
        try FentonHomeApp.audit(app) { try open(FentonHomeApp.ax5) }
    }

    /// The Account sheet, and Settings pushed inside it, in light.
    func testAccountSheetPassesAuditInLight() throws {
        func open(_ arguments: [String]) throws -> XCUIApplication {
            let app = try FentonHomeApp.launchSignedIn(arguments: arguments, environment: ["FENTON_APPEARANCE": "light"])
            app.openAccountSheet()
            sleep(1)
            return app
        }
        let app = try open([])
        assertSheet(app, isLight: true, "account")
        keepScreenshot(app, "light-account-\(layout)")
        try FentonHomeApp.audit(app) { try open(FentonHomeApp.ax5) }
    }
}
