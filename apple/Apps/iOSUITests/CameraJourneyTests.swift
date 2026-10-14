import XCTest

/// The camera viewer against the live server: WebRTC, the HLS fallback, the audit and screenshots.
@MainActor
final class CameraJourneyTests: JourneyTestCase {
    static let cameras = [("front_door", "Front Door"), ("garage_camera", "Driveway"),
                          ("upper_deck", "Upper Deck"), ("lower_deck", "Lower Deck")]

    /// The Home tile for a camera, scrolled into view.
    private func tile(_ app: XCUIApplication, _ streamId: String) -> XCUIElement {
        let tile = app.buttons["home.camera.\(streamId)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        for _ in 0..<4 where !tile.isHittable { app.swipeUp() }
        return tile
    }

    /// Opens the Front Door camera and returns its video element.
    private func openCamera(_ app: XCUIApplication, _ streamId: String = "front_door") -> XCUIElement {
        tile(app, streamId).tap()
        let video = app.descendants(matching: .any)["camera.viewer.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        return video
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 30) {
        let live = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: live, object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Camera stayed '\(element.value as? String ?? "")', expected '\(value)'")
    }

    /// Every tile opens its own camera wherever the tap lands. The fill-scaled Driveway picture (10:3 in a 16:9
    /// tile) used to overflow its tile and take taps meant for Front Door beside it.
    func testEveryTileOpensItsOwnCamera() throws {
        let app = try FentonHomeApp.launchSignedIn()
        _ = tile(app, "front_door")
        sleep(4) // Snapshots and live video load first: the overflow only existed once a picture was drawn.
        for (stream, title) in Self.cameras {
            for x in [0.08, 0.5, 0.92] {
                tile(app, stream).coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5),
                              "A tap at \(x) across the \(title) tile opened \(app.navigationBars.firstMatch.identifier)")
                app.buttons["sheet.close"].tap()
                XCTAssertTrue(app.buttons["home.camera.\(stream)"].waitForExistence(timeout: 5))
            }
        }
    }

    /// The viewer shows the tile's stream (web shared stream manager): a camera that is live on its tile is live
    /// the moment its viewer opens, with no reconnect.
    func testViewerSharesTheTilesLiveStream() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "webrtc"])
        let front = tile(app, "front_door")
        waitForValue(front, "Live")
        front.tap()
        let video = app.descendants(matching: .any)["camera.viewer.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        // Live on the first read: a fresh connection would read "Connecting to live video" for a second or more.
        XCTAssertEqual(video.value as? String, "Live", "The viewer attached to the tile's stream")
        app.buttons["sheet.close"].tap()
        XCTAssertEqual(tile(app, "front_door").value as? String, "Live", "The tile kept its stream")
    }

    /// Snapshot, Sound and Record (web `CameraModalContent`). Record is read, never pressed: it records on the house.
    func testViewerControls() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let video = openCamera(app)
        waitForValue(video, "Live")
        // Sound and Record are toggles (`.isToggle`), which XCUITest reports as switches.
        let sound = app.switches["camera.control.sound"]
        XCTAssertEqual(sound.label, "Sound")
        XCTAssertEqual(sound.value as? String, "Off", "Cameras open muted")
        // Tap the middle: XCUITest's switch tap aims at where a system switch's knob would be.
        let middle = sound.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.tap()
        waitForValue(sound, "On", timeout: 5)
        middle.tap()
        waitForValue(sound, "Off", timeout: 5)

        let record = app.switches["camera.control.record"]
        XCTAssertEqual(record.label, "Record")
        XCTAssertTrue(["Recording", "Not recording"].contains(record.value as? String ?? ""))

        let snapshot = app.buttons["camera.control.snapshot"]
        XCTAssertEqual(snapshot.label, "Snapshot")
        addUIInterruptionMonitor(withDescription: "Photos") { alert in
            for title in ["Allow", "Allow Access", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        // The runner grants Photos add access up front (`simctl privacy grant photos-add`); the monitor covers a prompt.
        snapshot.tap()
        // "Saved to Photos" shows for 2 s; poll faster than XCTWaiter's ~1 s so a short window is never missed.
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !seen.contains("Saved to Photos"), !app.alerts["Allow Photos Access"].exists {
            if let value = snapshot.value as? String, !value.isEmpty, seen.last != value { seen.append(value) }
            usleep(200_000)
        }
        XCTAssertFalse(app.alerts["Allow Photos Access"].exists, "Photos access was denied")
        XCTAssertTrue(seen.contains("Saved to Photos"), "Snapshot went through \(seen)")
        for control in [snapshot, sound, record] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
        }
        // Closing mutes: reopening starts muted again.
        middle.tap()
        waitForValue(sound, "On", timeout: 5)
        app.buttons["sheet.close"].tap()
        _ = openCamera(app)
        XCTAssertEqual(app.switches["camera.control.sound"].value as? String, "Off")
    }

    /// Video beside controls only where splits are allowed (iPad landscape); stacked everywhere else.
    func testViewerLayoutFollowsThePose() throws {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait } }
        let app = try FentonHomeApp.launchSignedIn()
        _ = openCamera(app)
        let window = app.windows.firstMatch.frame
        let splits = FentonHomeApp.family != .iPhone && window.width > window.height && window.width >= 1000
        let layout = app.descendants(matching: .any)[splits ? "camera.layout.split" : "camera.layout.stacked"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5), "\(FentonHomeApp.family) \(window.size)")
        let video = app.descendants(matching: .any)["camera.viewer.video"].frame
        let controls = app.buttons["camera.control.snapshot"].frame
        if splits {
            XCTAssertLessThanOrEqual(video.maxX, controls.minX, "Controls trail the video")
        } else {
            XCTAssertLessThanOrEqual(video.maxY, controls.minY, "Controls sit under the video")
        }
    }

    func testWebRTCGoesLive() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "webrtc"])
        waitForValue(openCamera(app), "Live")
    }

    func testHLSGoesLive() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "hls"])
        waitForValue(openCamera(app), "Live, a few seconds behind")
    }

    /// The default order (WebRTC, then HLS) reaches live video on every Home camera.
    func testEveryCameraGoesLive() throws {
        try assertEveryCameraGoesLive(FentonHomeApp.launchSignedIn(), NSPredicate(format: "value BEGINSWITH %@", "Live"))
    }

    /// WebRTC itself (not the HLS fallback) reaches live video on every Home camera.
    func testEveryCameraGoesLiveOverWebRTC() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "webrtc"])
        assertEveryCameraGoesLive(app, NSPredicate(format: "value == %@", "Live"))
    }

    private func assertEveryCameraGoesLive(_ app: XCUIApplication, _ live: NSPredicate) {
        for stream in ["front_door", "garage_camera", "upper_deck", "lower_deck"] {
            let video = openCamera(app, stream)
            let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: live, object: video)], timeout: 30)
            XCTAssertEqual(result, .completed, "\(stream) stayed '\(video.value as? String ?? "")'")
            app.buttons["Close"].tap()
        }
    }

    /// Backgrounding stops the stream; returning restarts it and the viewer goes live again.
    func testReturningFromBackgroundResumes() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let video = openCamera(app)
        waitForValue(video, "Live")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        waitForValue(video, "Live")
    }

    func testViewerPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        waitForValue(openCamera(app), "Live")
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.waitForValue(self.openCamera(large), "Live")
            return large
        }
    }

    /// Keeps a screenshot of the live viewer (blurred with `FENTON_REDACT_PRIVATE=1`) per pose.
    func testCaptureViewer() throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = try FentonHomeApp.launchSignedIn()
            waitForValue(openCamera(app), "Live", timeout: 45)
            sleep(1)
            keepScreenshot(app, "camera-\(suffix)")
            app.buttons["sheet.close"].tap()
            sleep(2)
            keepScreenshot(app, "camera-tiles-\(suffix)")
        }
        // Only iPad rotates here; setting the orientation on an unfolded Duo hangs the runner (devices.md).
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }
}
