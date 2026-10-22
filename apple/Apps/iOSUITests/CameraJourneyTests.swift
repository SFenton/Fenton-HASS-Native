import XCTest

/// The camera viewer against the live server: WebRTC, the HLS fallback, the audit and screenshots.
@MainActor
final class CameraJourneyTests: JourneyTestCase {
    static let cameras = [("front_door", "Front Door"), ("garage_camera", "Driveway"),
                          ("upper_deck", "Upper Deck"), ("lower_deck", "Lower Deck")]

    /// The Home tile for a camera, scrolled into view with its middle clear of the floating tab bar, so a tap near the
    /// tile's leading edge lands on the tile, not the bar's Home tab (the taller G weather card pushed the lower
    /// tiles behind the bar, 2026-10-15).
    private func tile(_ app: XCUIApplication, _ streamId: String) -> XCUIElement {
        let tile = app.buttons["home.camera.\(streamId)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        let clearBottom = app.windows.firstMatch.frame.maxY - 120
        for _ in 0..<5 where !tile.isHittable || tile.frame.midY > clearBottom { app.swipeUp() }
        return tile
    }

    /// Opens the Front Door camera and returns its video element.
    private func openCamera(_ app: XCUIApplication, _ streamId: String = "front_door") -> XCUIElement {
        tile(app, streamId).tap()
        let video = app.descendants(matching: .any)["camera.viewer.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        return video
    }

    /// Waits for live video over either transport: under host load WebRTC can miss its first-frame window and the
    /// viewer correctly falls back to HLS ("Live, a few seconds behind"). The WebRTC-only journeys stay strict.
    private func waitForLive(_ element: XCUIElement, timeout: TimeInterval = 30) {
        let live = NSPredicate(format: "value BEGINSWITH %@", "Live")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: live, object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Camera stayed '\(element.value as? String ?? "")', expected live video")
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
        waitForLive(video)
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
        snapshot.tap()
        // A fresh simulator asks for Photos add access: answer the system prompt from SpringBoard while polling.
        // "Saved to Photos" shows for 2 s; poll faster than XCTWaiter's ~1 s so a short window is never missed.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !seen.contains("Saved to Photos"), !app.alerts["Allow Photos Access"].exists {
            let prompt = springboard.alerts.firstMatch
            if prompt.exists, let allow = ["Allow", "Allow Access", "OK"].lazy.map({ prompt.buttons[$0] }).first(where: \.exists) {
                allow.tap()
            }
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
        let snapshot = app.buttons["camera.control.snapshot"]
        XCTAssertTrue(snapshot.wait(for: \.isHittable, toEqual: true, timeout: 10))
        sleep(1) // Measure after the page sheet settles, not mid-presentation.
        let video = app.descendants(matching: .any)["camera.viewer.video"].firstMatch.frame
        let controls = snapshot.frame
        add(XCTAttachment(string: "video \(video), controls \(controls)\n\(app.debugDescription)"))
        // The element must have a real frame (VoiceOver outlines it): a clear overlay without an accessibility shape came
        // back as a zero frame on iPhone and the folded Duo (2026-10-17).
        XCTAssertGreaterThan(video.width, 100, "The video element has no frame: \(video)")
        XCTAssertGreaterThan(video.height, 60, "The video element has no frame: \(video)")
        XCTAssertTrue(window.contains(video), "The video element lies outside the window: \(video)")
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
        waitForLive(video)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        waitForLive(video)
    }

    /// Home's tiles come back live after a background long enough for the app's websocket to be torn down
    /// (`ConnectionLifecycle.backgroundGrace` is 30 s): owner report 2026-10-16, "cameras are not reconnecting on
    /// backgrounding and re-opening". Every tile is live before, and every tile is live again after, with the
    /// snapshot (never a blank) in between.
    func testHomeTilesResumeAfterALongBackground() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let streams = Self.cameras.map(\.0)
        for stream in streams { waitForValue(tile(app, stream), "Live", timeout: 45) }
        XCUIDevice.shared.press(.home)
        sleep(60)
        app.activate()
        for stream in streams {
            let element = tile(app, stream)
            XCTAssertTrue(element.exists, "\(stream) tile is still on Home")
            waitForValue(element, "Live", timeout: 60)
        }
    }

    /// The cards are nearly square like the web's (1 : 0.78) on Home and Security, whatever the camera's own shape
    /// (the Driveway is 10:3), and the viewer keeps each camera's own aspect ratio (owner request 2026-10-16).
    func testCardsAreNearSquareAndTheViewerKeepsItsAspect() throws {
        let app = try FentonHomeApp.launchSignedIn()
        func assertSquare(_ element: XCUIElement, _ name: String) {
            let ratio = element.frame.height / element.frame.width
            XCTAssertEqual(ratio, 0.78, accuracy: 0.03, "\(name) card is \(element.frame.size), not 1 : 0.78")
        }
        for (stream, title) in Self.cameras { assertSquare(tile(app, stream), "Home \(title)") }
        // Two tiles in a row share a height, so the grid is even.
        XCTAssertEqual(tile(app, "front_door").frame.height, tile(app, "garage_camera").frame.height, accuracy: 1)
        openSection("security", title: "Security", in: app)
        for (stream, title) in Self.cameras { assertSquare(securityTile(app, stream), "Security \(title)") }
        openSection("home", title: "Home", in: app)
        _ = openCamera(app)
        XCTAssertTrue(app.buttons["camera.control.snapshot"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        sleep(1) // Measure after the page sheet settles, not mid-presentation.
        // The video element itself reports no frame (a clear overlay), so measure what it pushes down: in the stacked
        // layout the controls start one section gap below a 4:3 picture as wide as the controls.
        let stack = app.descendants(matching: .any)["camera.layout.stacked"]
        if stack.exists {
            let controls = app.descendants(matching: .any)["Front Door camera controls"].firstMatch
            let expected = controls.frame.width * 3 / 4 + 24
            XCTAssertEqual(controls.frame.minY - stack.frame.minY, expected, accuracy: 4,
                           "The viewer keeps the camera's own 4:3 (controls \(controls.frame), page \(stack.frame))")
        }
        keepScreenshot(app, "camera-viewer-aspect-\(layout)")
    }

    /// Security's tile for a camera, scrolled into view with its middle clear of the floating tab bar.
    private func securityTile(_ app: XCUIApplication, _ streamId: String) -> XCUIElement {
        let tile = app.buttons["security.camera.\(streamId)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "\(streamId) has no tile on Security")
        let clearBottom = app.windows.firstMatch.frame.maxY - 120
        for _ in 0..<6 where !tile.isHittable || tile.frame.midY > clearBottom { app.swipeUp() }
        return tile
    }

    /// Security shows the streams Home already has (owner report 2026-10-16: "delayed on the Security tab while live on
    /// Home"). Every tile is live on Home; on the first read after Security's tile is on screen it is live too, with no
    /// second connect, and Home's tiles are still live when the owner goes back.
    func testSecurityTilesShowTheStreamsHomeAlreadyHas() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "webrtc"])
        let streams = Self.cameras.map(\.0)
        for stream in streams { waitForValue(tile(app, stream), "Live", timeout: 45) }
        openSection("security", title: "Security", in: app)
        for stream in streams {
            let element = securityTile(app, stream)
            // A fresh connection reads "Snapshot" for a second or more, so a live read here is the shared stream.
            XCTAssertEqual(element.value as? String, "Live", "Security's \(stream) tile did not attach to Home's live stream")
        }
        openSection("home", title: "Home", in: app)
        for stream in streams { XCTAssertEqual(tile(app, stream).value as? String, "Live", "Home's \(stream) tile kept its stream") }
    }

    /// Streams no page shows are paused (perf pass 2: a page with no camera still decoded all four). Behind another tab for
    /// longer than the pool's 4 s grace they stop, and returning to Home brings every one live again without reopening
    /// anything. The quick switch to Security above never pauses.
    func testStreamsPauseBehindAnotherTabAndComeBackWhenHomeIsShownAgain() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "webrtc"])
        let streams = Self.cameras.map(\.0)
        for stream in streams { waitForValue(tile(app, stream), "Live", timeout: 45) }
        openSection("chores", title: "Chores", in: app)
        sleep(8)
        openSection("home", title: "Home", in: app)
        // Live again, every camera, from the pool's paused state.
        for stream in streams { waitForValue(tile(app, stream), "Live", timeout: 45) }
    }

    /// A live stream whose frames stop goes back to its snapshot and comes back by itself (web `FRAME_STALL_MS`). The
    /// debug fault `FENTON_CAMERA_FREEZE_ONCE` stops the Front Door's frame count after it first goes live, as a camera
    /// that stops sending does; the watchdog takes the stream down after about 8 s (the tile reads Snapshot and drops its
    /// live dot) and the pool's retry brings it back live. The other tiles are never touched.
    func testAStalledStreamFallsBackToItsSnapshotAndComesBack() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_CAMERA_MODE": "webrtc", "FENTON_CAMERA_FREEZE_ONCE": "front_door"])
        let front = tile(app, "front_door")
        waitForValue(front, "Live", timeout: 45)
        var sawSnapshot = false
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline, !sawSnapshot {
            sawSnapshot = (front.value as? String) == "Snapshot"
            if !sawSnapshot { usleep(250_000) }
        }
        XCTAssertTrue(sawSnapshot, "The frozen stream stayed '\(front.value as? String ?? "")' instead of falling back to its snapshot")
        waitForValue(front, "Live", timeout: 60)
        for stream in ["garage_camera", "upper_deck", "lower_deck"] {
            XCTAssertEqual(tile(app, stream).value as? String, "Live", "\(stream) was not affected")
        }
    }

    /// The viewer, left open across a long background, is live again on return.
    func testViewerResumesAfterALongBackground() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let video = openCamera(app)
        waitForLive(video)
        XCUIDevice.shared.press(.home)
        sleep(60)
        app.activate()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        waitForLive(video, timeout: 60)
    }

    func testViewerPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        waitForLive(openCamera(app))
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.waitForLive(self.openCamera(large))
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
            waitForLive(openCamera(app), timeout: 45)
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
