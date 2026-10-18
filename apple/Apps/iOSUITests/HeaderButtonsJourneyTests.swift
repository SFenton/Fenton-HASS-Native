import XCTest

/// The shell's two trailing header buttons after the owner's 2026-10-18 decision (option A, FestivalNativeApps parity;
/// `.agents/design/direction-g.md`, Navigation): Profile with a known name is a 44 pt monogram disc that is the whole button
/// (no glass ring), Profile without a name is the person symbol on the bar's glass, and Quick Links stays a separate glass
/// circle 12 pt away. Runs on the `shell-header` gallery on iPhone, the iPhone Duo (folded and unfolded) and iPad, with no
/// sign-in.
///
/// XCUITest reports a glass bar item's frame several points inside its circle (and the disc's frame includes its badge), so
/// sizes and gaps are measured from the screenshot's pixels on a plain black page (``HeaderPixels``), the way the owner
/// reads them.
@MainActor
final class HeaderButtonsJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    private func launch(profile: String? = nil, badge: Int = 0, scheme: String = "dark", pushed: Bool = false, plain: Bool = true,
                        arguments: [String] = []) -> XCUIApplication {
        var environment = ["FENTON_GALLERY_BADGE": "\(badge)", "FENTON_GALLERY_SCHEME": scheme]
        if let profile { environment["FENTON_GALLERY_PROFILE"] = profile }
        if pushed { environment["FENTON_GALLERY_PUSHED"] = "1" }
        if plain { environment["FENTON_GALLERY_PLAIN"] = "1" }
        let app = FentonHomeApp.launchGallery("shell-header", arguments: arguments, environment: environment)
        XCTAssertTrue(app.buttons["nav.profile"].waitForExistence(timeout: 20), "No Profile button")
        XCTAssertTrue(app.buttons["quickLinks.open"].exists, "No Quick Links button")
        sleep(2) // Let the bar settle.
        return app
    }

    /// Saves a screenshot to `FENTON_SHOTS_DIR` (never the repository) and attaches it for the result bundle.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(layout)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(layout)-\(name).png"))
    }

    private func pixels(_ app: XCUIApplication) -> HeaderPixels {
        let measured = HeaderPixels(screenshot: app.screenshot(), windowWidth: app.windows.firstMatch.frame.width)
        print("HEADERPIXELS \(layout) disc=\(String(describing: measured.disc)) glass=\(measured.glass) window=\(app.windows.firstMatch.frame)")
        return measured
    }

    /// The bar draws both buttons side by side. The folded Duo moves bar items into its vertical rail (system behaviour),
    /// where no horizontal gap exists.
    private func isHorizontal(_ app: XCUIApplication) -> Bool {
        abs(app.buttons["quickLinks.open"].frame.midY - app.buttons["nav.profile"].frame.midY) < 12
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].firstMatch.label.replacingOccurrences(of: "Last action: ", with: "")
    }

    private func tap(_ x: CGFloat, _ y: CGFloat, in app: XCUIApplication) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
        usleep(400_000)
    }

    // MARK: - Named profile

    /// The monogram disc is 44 pt, is the whole button (no glass ring around it), sits 12 pt from Quick Links' 44 pt glass
    /// circle, and both keep their labels, identifiers and the spoken value.
    func testNamedProfileFillsItsContainerNextToQuickLinks() {
        let app = launch(profile: "Stephen Fenton", badge: 3)
        let profile = app.buttons["nav.profile"]
        let links = app.buttons["quickLinks.open"]
        XCTAssertEqual(profile.label, "Profile")
        XCTAssertEqual(profile.value as? String, "Stephen Fenton, 3 items need attention")
        XCTAssertEqual(links.label, "Quick Links")
        XCTAssertTrue(profile.isHittable)
        XCTAssertTrue(links.isHittable)
        XCTAssertFalse(links.frame.intersects(profile.frame.insetBy(dx: 2, dy: 2)), "The buttons overlap")
        XCTAssertGreaterThanOrEqual(min(profile.frame.width, profile.frame.height), 36)
        shoot(app, "named-plain")
        guard isHorizontal(app) else {
            // The folded Duo's rail takes Quick Links in; the monogram, a custom view, stays in the top bar (it cannot go
            // vertical). The disc is still 44 pt, and the two do not overlap.
            XCTAssertNotEqual(links.frame.minY, profile.frame.minY, "The rail stacks the buttons")
            if let disc = pixels(app).disc {
                XCTAssertEqual(disc.width, 44, accuracy: 1, "The monogram is not 44 pt in the Duo's rail layout")
            } else {
                XCTFail("No monogram disc in the screenshot")
            }
            return
        }
        XCTAssertLessThan(links.frame.maxX, profile.frame.minX + 1, "Quick Links is not before Profile")
        let measured = pixels(app)
        guard let disc = measured.disc else { return XCTFail("No monogram disc in the screenshot") }
        XCTAssertEqual(disc.width, 44, accuracy: 1, "The monogram is not 44 pt")
        XCTAssertEqual(disc.height, 44, accuracy: 1)
        guard let glass = measured.glass.last(where: { $0.upperBound <= disc.minX + 1 }) else { return XCTFail("No Quick Links glass") }
        XCTAssertEqual(glass.upperBound - glass.lowerBound, 44, accuracy: 1, "Quick Links' glass is not a 44 pt circle")
        let gap = disc.minX - glass.upperBound
        XCTAssertEqual(gap, 12, accuracy: 1.5, "The gap between Quick Links and Profile is \(gap) pt")
        XCTAssertLessThanOrEqual(gap, 14)
        // No glass ring: nothing but the disc (and its badge) is drawn right of it.
        XCTAssertNil(measured.glass.first { $0.lowerBound > disc.maxX - 1 }, "Something is drawn past the disc")
    }

    /// Each button opens its own action from 19 pt off its centre, inside the 44 pt target and outside what XCUITest reports
    /// for a glass bar item.
    func testBothButtonsHaveA44PointTarget() {
        let app = launch(profile: "Stephen Fenton", badge: 3)
        guard isHorizontal(app) else {
            app.buttons["quickLinks.open"].tap()
            XCTAssertEqual(lastAction(app), "quick-links")
            app.buttons["nav.profile"].tap()
            XCTAssertEqual(lastAction(app), "profile")
            return
        }
        let measured = pixels(app)
        guard let disc = measured.disc, let glass = measured.glass.last(where: { $0.upperBound <= disc.minX + 1 }) else {
            return XCTFail("Could not measure the buttons")
        }
        let y = disc.midY
        let linksX = (glass.lowerBound + glass.upperBound) / 2
        for (name, x, yy, expected) in [("Quick Links left", linksX - 19, y, "quick-links"), ("Profile left", disc.midX - 19, y, "profile"),
                                        ("Quick Links right", linksX + 19, y, "quick-links"), ("Profile right", disc.midX + 19, y, "profile"),
                                        ("Profile above", disc.midX, y - 19, "profile"), ("Profile below", disc.midX, y + 19, "profile"),
                                        ("Quick Links above", linksX, y - 19, "quick-links"), ("Quick Links below", linksX, y + 19, "quick-links")] {
            // Tap the other button first so a miss cannot pass on the previous value.
            tap(expected == "profile" ? linksX : disc.midX, y, in: app)
            XCTAssertNotEqual(lastAction(app), expected)
            tap(x, yy, in: app)
            XCTAssertEqual(lastAction(app), expected, "\(name): a tap 19 pt from the centre did not reach the button")
        }
    }

    /// At the largest text size the bar items keep their size (HIG Toolbars; the Large Content Viewer shows them bigger).
    func testBarKeepsItsSizesAtAX5() {
        let app = launch(profile: "Stephen Fenton", badge: 3, arguments: FentonHomeApp.ax5)
        let profile = app.buttons["nav.profile"]
        XCTAssertTrue(profile.isHittable)
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable)
        XCTAssertEqual(profile.value as? String, "Stephen Fenton, 3 items need attention")
        shoot(app, "named-ax5")
        guard isHorizontal(app) else { return }
        let measured = pixels(app)
        guard let disc = measured.disc else { return XCTFail("No monogram disc at AX5") }
        XCTAssertEqual(disc.width, 44, accuracy: 1, "The disc grew with text size")
        guard let glass = measured.glass.last(where: { $0.upperBound <= disc.minX + 1 }) else { return XCTFail("No Quick Links glass") }
        XCTAssertEqual(disc.minX - glass.upperBound, 12, accuracy: 1.5)
    }

    // MARK: - Unnamed profile

    /// With no name yet Profile is the person symbol on the standard 44 pt glass circle, 12 pt from Quick Links.
    func testUnnamedProfileIsAGlassSymbol() {
        let app = launch(profile: "none")
        let profile = app.buttons["nav.profile"]
        XCTAssertEqual(profile.label, "Profile")
        XCTAssertEqual(profile.value as? String ?? "", "")
        XCTAssertTrue(profile.isHittable)
        shoot(app, "unnamed-plain")
        if isHorizontal(app) {
            let measured = pixels(app)
            XCTAssertNil(measured.disc, "The monogram's blue disc shows with no name")
            let circles = measured.glass.suffix(2)
            if circles.count == 2, let links = circles.first, let symbol = circles.last {
                XCTAssertEqual(links.upperBound - links.lowerBound, 44, accuracy: 1)
                XCTAssertEqual(symbol.upperBound - symbol.lowerBound, 44, accuracy: 1, "The symbol's glass is not a 44 pt circle")
                XCTAssertEqual(symbol.lowerBound - links.upperBound, 12, accuracy: 1.5)
            } else {
                XCTFail("Expected two glass circles, saw \(measured.glass)")
            }
        }
        profile.tap()
        XCTAssertEqual(lastAction(app), "profile")
    }

    // MARK: - Other states

    /// The spoken value says the count; a pushed page keeps both buttons trailing and the disc the same size.
    func testBadgeValueAndPushedPage() {
        var app = launch(profile: "Stephen Fenton", badge: 12)
        XCTAssertEqual(app.buttons["nav.profile"].value as? String, "Stephen Fenton, 12 items need attention")
        shoot(app, "named-badge9plus")
        app = launch(profile: "Stephen Fenton", badge: 1)
        XCTAssertEqual(app.buttons["nav.profile"].value as? String, "Stephen Fenton, 1 item needs attention")
        app = launch(profile: "Stephen Fenton", badge: 3, pushed: true)
        XCTAssertTrue(app.buttons["quickLinks.open"].exists)
        shoot(app, "pushed-plain")
        if isHorizontal(app), let disc = pixels(app).disc {
            XCTAssertEqual(disc.width, 44, accuracy: 1, "The disc changed on a pushed page")
        }
    }

    // MARK: - Captures

    /// Every state on the house backdrop and on the plain page, in the dark and light schemes, for design review.
    func testCaptureEveryState() {
        for scheme in ["dark", "light"] {
            for (state, profile, badge, pushed) in [("named", "Stephen Fenton", 0, false), ("named-badge3", "Stephen Fenton", 3, false),
                                                    ("named-badge9plus", "Stephen Fenton", 12, false), ("unnamed", "none", 0, false),
                                                    ("pushed", "Stephen Fenton", 3, true)] {
                let app = launch(profile: profile, badge: badge, scheme: scheme, pushed: pushed, plain: false)
                shoot(app, "\(state)-\(scheme)")
                let plain = launch(profile: profile, badge: badge, scheme: scheme, pushed: pushed, plain: true)
                shoot(plain, "\(state)-plain-\(scheme)")
            }
        }
    }
}

// MARK: - Pixel measurement

/// Where the header's blue monogram disc and glass circles are in a screenshot of the plain black gallery page, in points.
struct HeaderPixels {
    /// The bounding box of the monogram's blue disc (`ProfileButton.fill`), nil when none is drawn.
    var disc: CGRect?
    /// The horizontal extents of the glass circles (and the disc) right of the window's middle, leading to trailing.
    var glass: [ClosedRange<CGFloat>] = []

    init(screenshot: XCUIScreenshot, windowWidth: CGFloat) {
        guard let image = screenshot.image.cgImage else { return }
        let scale = CGFloat(image.width) / windowWidth
        let width = image.width
        let rows = min(image.height, Int(220 * scale))
        var buffer = [UInt8](repeating: 0, count: width * rows * 4)
        guard let context = CGContext(data: &buffer, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // The context's origin is bottom-left; drawing the image shifted up keeps its top rows.
        context.draw(image, in: CGRect(x: 0, y: rows - image.height, width: width, height: image.height))
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
        }
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1, count = 0
        for y in 0..<rows {
            for x in 0..<width {
                let p = pixel(x, y)
                if abs(p.r - 0) < 40, abs(p.g - 102) < 40, abs(p.b - 204) < 40 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y); count += 1
                }
            }
        }
        var bandStart = Int(50 * scale), bandEnd = Int(120 * scale)
        if count > 200 {
            disc = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX + 1 - minX) / scale, height: CGFloat(maxY + 1 - minY) / scale)
            bandStart = minY; bandEnd = maxY + 1
        }
        var start: Int?
        var last = 0
        var clusters: [ClosedRange<CGFloat>] = []
        for x in Int(CGFloat(width) * 0.5)..<width {
            var bright = 0
            for y in bandStart..<min(bandEnd, rows) {
                let p = pixel(x, y)
                if Double(p.r) * 0.3 + Double(p.g) * 0.59 + Double(p.b) * 0.11 > 14 { bright += 1 }
            }
            if bright > 3 {
                if start == nil { start = x }
                last = x
            } else if let s = start, CGFloat(x - last) > 2 * scale {
                if CGFloat(last + 1 - s) / scale > 6 { clusters.append(CGFloat(s) / scale...CGFloat(last + 1) / scale) }
                start = nil
            }
        }
        if let s = start, CGFloat(last + 1 - s) / scale > 6 { clusters.append(CGFloat(s) / scale...CGFloat(last + 1) / scale) }
        glass = clusters
    }
}
