import XCTest

/// The camera viewer against the live server: WebRTC, the HLS fallback, the audit and screenshots.
@MainActor
final class CameraJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Opens the Front Door camera and returns its video element.
    private func openCamera(_ app: XCUIApplication, _ streamId: String = "front_door") -> XCUIElement {
        let tile = app.buttons["home.camera.\(streamId)"]
        if !tile.isHittable { app.swipeUp() }
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let video = app.descendants(matching: .any)["camera.viewer.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        return video
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 30) {
        let live = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: live, object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Camera stayed '\(element.value as? String ?? "")', expected '\(value)'")
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
        let app = try FentonHomeApp.launchSignedIn()
        for stream in ["front_door", "garage_camera", "upper_deck", "lower_deck"] {
            let video = openCamera(app, stream)
            let live = NSPredicate(format: "value BEGINSWITH %@", "Live")
            let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: live, object: video)], timeout: 30)
            XCTAssertEqual(result, .completed, "\(stream) stayed '\(video.value as? String ?? "")'")
            app.buttons["Done"].tap()
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
            waitForValue(openCamera(app), "Live")
            sleep(1)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "camera-\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
