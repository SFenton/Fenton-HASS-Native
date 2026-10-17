import XCTest

/// Tile layout and chevron geometry on the Direction G gallery's Tile Layouts section
/// (`FENTON_GALLERY=direction-g`, `-directionGOrder layouts`, `-directionGLayout <layout>`): the four arrangements
/// compared for the owner (2026-10-16: "it feels too high up / lots of dead space"), the shipped row's centring, the
/// chevron's vertical centre, equal row heights and 44 pt targets at the default size and AX5 on iPhone, folded Duo
/// and iPad. Positions are read from screenshots (`TileGeometry`) because a tile's glyph and chevron are hidden from
/// VoiceOver.
@MainActor
final class TileLayoutJourneyTests: JourneyTestCase {
    private static let layouts = ["row", "anchoredBottom", "centeredStack", "stackedTop"]

    private func launch(_ layout: String, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.launchGallery("direction-g", arguments: ["-directionGOrder", "layouts", "-directionGLayout", layout] + arguments)
        XCTAssertTrue(element("g.layout.\(layout).Kitchen", in: app).waitForExistence(timeout: 20), "\(layout) did not appear")
        sleep(1) // Mid-animation frames move the ink.
        return app
    }

    private func tile(_ layout: String, _ name: String, in app: XCUIApplication) -> XCUIElement {
        element("g.layout.\(layout).\(name)", in: app)
    }

    private func capture(_ file: StaticString = #filePath, _ line: UInt = #line) throws -> RenderedContrast.Capture {
        try XCTUnwrap(RenderedContrast.Capture.screen(), "No screen capture", file: file, line: line)
    }

    /// Every arrangement keeps 44 pt targets, equal heights within a row, and the rows get shorter the closer the
    /// arrangement is to Apple Home's tile.
    func testEveryLayoutKeepsTargetsAndEqualRowHeights() {
        var heights: [String: CGFloat] = [:]
        for layout in Self.layouts {
            let app = launch(layout)
            for name in ["Office Lamp", "Living Room Purifier", "Master Bedroom Closet", "Kitchen", "Security", "Towel Rack"] {
                let element = tile(layout, name, in: app)
                XCTAssertTrue(element.exists, "\(layout) \(name)")
                assertTarget(element)
            }
            // Two columns on iPhone: tiles in the same row share a height (the grid's equal row heights).
            let closet = tile(layout, "Master Bedroom Closet", in: app), kitchen = tile(layout, "Kitchen", in: app)
            if abs(closet.frame.minY - kitchen.frame.minY) < 2 {
                XCTAssertEqual(closet.frame.height, kitchen.frame.height, accuracy: 1, "\(layout) row heights differ")
            }
            // The shortest tile in the grid: a wrapped title lifts its whole row, so the single-line rows show the layout.
            heights[layout] = ["Office Lamp", "Kitchen", "Towel Rack"].map { tile(layout, $0, in: app).frame.height }.min()
            keepScreenshot(app, "tile-layout-\(layout)-\(self.layout)")
        }
        XCTAssertLessThan(heights["row"] ?? .infinity, heights["stackedTop"] ?? 0, "The row is shorter than the old stack: \(heights)")
        XCTAssertLessThanOrEqual(heights["row"] ?? .infinity, 100, "A row tile stays Apple Home's height: \(heights)")
    }

    /// The chevron sits at the tile's vertical centre in every arrangement.
    func testChevronIsVerticallyCentred() throws {
        for layout in Self.layouts {
            let app = launch(layout)
            for name in ["Kitchen", "Security"] {
                let element = tile(layout, name, in: app)
                // The Security tile is dark (the page module), the Kitchen tile a flat room fill; the chevron is
                // read against the corner colour either way.
                let capture = try capture()
                guard let chevron = TileGeometry.chevron(in: element.frame, capture: capture) else {
                    XCTFail("\(layout) \(name): no chevron found"); continue
                }
                XCTAssertEqual(chevron.midY, element.frame.midY, accuracy: 3,
                               "\(layout) \(name): chevron midY \(chevron.midY) vs tile midY \(element.frame.midY)")
                XCTAssertGreaterThan(chevron.minX, element.frame.maxX - 32, "\(layout) \(name): chevron is trailing")
            }
        }
    }

    /// The shipped row puts the glyph and title at the tile's vertical centre; the anchored layout puts the title at the
    /// bottom edge and the glyph at the top; neither floats near the top with dead space under it.
    func testRowIsCentredAndAnchoredTextSitsAtTheBottom() throws {
        let row = launch("row")
        let kitchen = tile("row", "Kitchen", in: row)
        let rowFrame = kitchen.frame
        let rowContent = try XCTUnwrap(TileGeometry.content(in: rowFrame, capture: try capture()), "row: no content")
        XCTAssertEqual(rowContent.midY, rowFrame.midY, accuracy: 4, "row content is vertically centred")

        let anchored = launch("anchoredBottom")
        let tile2 = tile("anchoredBottom", "Kitchen", in: anchored)
        let content = try XCTUnwrap(TileGeometry.content(in: tile2.frame, capture: try capture()), "anchored: no content")
        XCTAssertLessThan(tile2.frame.maxY - content.maxY, 22, "anchored text sits at the bottom padding")
        XCTAssertLessThan(content.minY - tile2.frame.minY, 22, "anchored glyph sits at the top padding")

        let stacked = launch("stackedTop")
        let old = tile("stackedTop", "Kitchen", in: stacked)
        let oldContent = try XCTUnwrap(TileGeometry.content(in: old.frame, capture: try capture()), "stackedTop: no content")
        XCTAssertGreaterThan(old.frame.maxY - oldContent.maxY, rowFrame.maxY - rowContent.maxY + 8,
                             "The old stack left more dead space under its text")
    }

    /// At AX5 a row falls back to the bottom-anchored stack: targets hold, nothing clips off the tile, and the shipped
    /// layout passes the accessibility audit.
    func testAX5KeepsTilesReadable() throws {
        for layout in Self.layouts {
            let app = launch(layout, arguments: FentonHomeApp.ax5)
            let window = app.windows.firstMatch.frame
            for name in ["Master Bedroom Closet", "Kitchen", "Security"] {
                let element = tile(layout, name, in: app)
                XCTAssertTrue(element.exists, "\(layout) \(name) at AX5")
                assertTarget(element)
                XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX + 1, "\(layout) \(name) is clipped at AX5")
            }
            keepScreenshot(app, "tile-layout-\(layout)-ax5-\(self.layout)")
        }
        let shipped = launch("row")
        try FentonHomeApp.audit(shipped) { self.launch("row", arguments: FentonHomeApp.ax5) }
    }
}
