#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
import HassTestSupport
@testable import HassUI
import SwiftUI
import Testing

/// Presses the camera viewer's Snapshot, Sound and Record controls in a real window, stacked under the video on a
/// phone and beside it in a wide window, with no stream playing (the pool has no modes, so the camera shows its
/// still).
@MainActor
@Suite(.serialized, .enabled(if: AXWindow.isAvailable, "Needs accessibility permission for the test host"))
struct CameraViewerFlowTests {
    static let phone = CGSize(width: 402, height: 874)
    static let wide = CGSize(width: 1210, height: 834)

    /// The viewer for `camera` with its record call sent to `caller`, and its recording script reporting `on` or `off`.
    func open(_ camera: HomeConfig.Camera, caller: RecordingCaller, size: CGSize, recording: Bool = false) -> AXWindow {
        let store = EntityStore()
        if let id = camera.recordingEntityId {
            store.replaceAll([EntityState(entityId: id, state: recording ? "on" : "off", attributes: [:])])
        }
        let connection = HassConnection(server: AppSessionTests.server, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let pool = CameraStreamPool(modes: [], observesApp: false)
        return AXWindow(
            CameraViewer(camera: camera, caller: caller)
                .environment(connection).environment(store).environment(\.cameraStreamPool, pool),
            size: size
        )
    }

    @Test func theControlsSnapshotMuteAndRecordUnderTheVideoOnAPhone() async throws {
        let camera = try #require(HomeConfig.cameras.first { $0.recordCall != nil })
        let caller = RecordingCaller()
        let driver = open(camera, caller: caller, size: Self.phone)
        defer { driver.close() }
        let snapshot = try #require(await driver.waitFor("camera.control.snapshot"))
        #expect(snapshot.spoken == "Snapshot")
        // With no frame playing and no still to fetch there is nothing to save, and the control says so.
        #expect(await driver.press("camera.control.snapshot") { nodes in
            nodes.first { $0.identifier == "camera.control.snapshot" }?.value == "Couldn't save the snapshot"
        }, "a snapshot with nothing to save reports it")
        let sound = try #require(await driver.node("camera.control.sound"))
        #expect(sound.value == "Off", "cameras open muted")
        #expect(await driver.press("camera.control.sound") { nodes in
            nodes.first { $0.identifier == "camera.control.sound" }?.value == "On"
        }, "Sound turns the audio on")
        #expect(await driver.press("camera.control.record") { _ in true })
        for _ in 0..<200 where caller.calls.isEmpty { await driver.window.settle(0.05) }
        #expect(!caller.calls.isEmpty, "Record runs the camera's script")
    }

    @Test func aRecordingCameraShowsItsStateAndTheControlsSitBesideTheVideoInAWideWindow() async throws {
        let camera = try #require(HomeConfig.cameras.first { $0.recordCall != nil && $0.recordingEntityId != nil })
        let caller = RecordingCaller()
        let driver = open(camera, caller: caller, size: Self.wide, recording: true)
        defer { driver.close() }
        let record = await driver.waitFor("camera.control.record")
        #expect(record?.value == "Recording")
        #expect(await driver.press("camera.control.record") { _ in true })
        for _ in 0..<200 where caller.calls.isEmpty { await driver.window.settle(0.05) }
        #expect(!caller.calls.isEmpty, "Record while recording sends the call that stops it")
    }

    @Test func aCameraWithNoRecordingStateSendsItsScriptWithoutWaitingForOne() async throws {
        var camera = HomeConfig.cameras[0]
        camera.recordingEntityId = nil
        #expect(camera.recordCall != nil)
        let caller = RecordingCaller()
        let driver = open(camera, caller: caller, size: Self.phone)
        defer { driver.close() }
        #expect(await driver.press("camera.control.record") { _ in true })
        for _ in 0..<200 where caller.calls.isEmpty { await driver.window.settle(0.05) }
        #expect(!caller.calls.isEmpty)
    }
}
#endif
