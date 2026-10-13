import CoreGraphics
import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// The shared camera stream pool, the viewer's controls and layout, and hosted renders of the tile and viewer.
@MainActor
struct CameraControlsTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tabletLandscape = CGSize(width: 1210, height: 834)

    private func connection(_ store: EntityStore = EntityStore()) -> HassConnection {
        HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
    }

    // MARK: Pool

    @Test func tilesAndViewersShareOneModelPerCamera() {
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let front = HomeConfig.cameras[0]
        let tile = pool.appear(front, connection: connection())
        let viewer = pool.appear(front, connection: connection())
        #expect(tile === viewer)
        #expect(pool.model(for: HomeConfig.cameras[1]) !== tile)
    }

    @Test func aCameraWithNoModesFailsAndDropsItsRetention() {
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let front = HomeConfig.cameras[0]
        let model = pool.appear(front, connection: connection())
        #expect(model.state.phase == .failed)
        #expect(!model.isRunning)
        pool.disappear(front)
        #expect(!pool.shouldRun(front))
    }

    @Test func shownCamerasStayRetainedUntilTheBackground() {
        let pool = CameraStreamPool(modes: [.webRTC], observesApp: false)
        let front = HomeConfig.cameras[0]
        pool.disappear(front) // Disappearing before appearing is harmless.
        let model = pool.appear(front, connection: connection())
        #expect(model.isRunning)
        pool.disappear(front)
        #expect(pool.shouldRun(front))
        model.setMuted(false)
        pool.enterBackground()
        #expect(!model.isRunning)
        #expect(model.isMuted, "Sound never plays behind the app")
        pool.enterForeground()
        #expect(model.isRunning)
        model.stop()
    }

    @Test func retryRestartsTheCamera() {
        let pool = CameraStreamPool(modes: [.hls], observesApp: false)
        let front = HomeConfig.cameras[0]
        pool.retry(front, connection: connection())
        #expect(pool.model(for: front).isRunning)
        pool.model(for: front).stop()
        #expect(!pool.model(for: front).isRunning)
    }

    @Test func muteReportsChangesOnce() {
        let model = CameraLiveModel(camera: HomeConfig.cameras[0], modes: [])
        var changes = 0
        model.onMuteChange = { changes += 1 }
        #expect(model.isMuted, "Cameras open muted")
        model.setMuted(true)
        model.setMuted(false)
        model.setMuted(false)
        #expect(!model.isMuted)
        #expect(changes == 1)
        #expect(model.liveFrame() == nil, "Nothing is playing")
    }

    // MARK: Controls

    @Test func snapshotFeedbackReadsItsOutcome() {
        #expect(CameraSnapshotFeedback.idle.title == "Snapshot")
        #expect(CameraSnapshotFeedback.saving.title == "Snapshot")
        #expect(CameraSnapshotFeedback.saved.title == "Saved")
        #expect(CameraSnapshotFeedback.failed.title == "Not Saved")
        #expect(CameraSnapshotFeedback.saved.accessibilityValue == "Saved to Photos")
        #expect(CameraSnapshotFeedback.failed.accessibilityValue == "Couldn't save the snapshot")
        #expect(CameraSnapshotFeedback.saving.accessibilityValue == "Saving")
        #expect(CameraSnapshotFeedback.idle.accessibilityValue.isEmpty)
        #expect(Set([CameraSnapshotFeedback.idle, .saving, .saved, .failed].map(\.symbol)).count == 3)
    }

    @Test func snapshotsEncodeAsJPEG() throws {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let data = try #require(CameraSnapshotSaver.jpeg(image))
        #expect(data.starts(with: [0xFF, 0xD8]), "JPEG start-of-image marker")
    }

    @Test func savingWithNothingToSaveFails() async {
        #expect(await CameraSnapshotSaver.save(frame: nil, fallbackURL: nil) == .failed)
    }

    @Test func recordCallsTheCamerasScript() async throws {
        let caller = NullCaller()
        let call = try #require(HomeConfig.cameras[0].recordCall)
        try await caller.call(call)
        #expect(caller.calls == ["script.turn_on"])
    }

    // MARK: Layout

    @Test func viewerSplitsOnlyWhereSplitsAreAllowed() {
        let wide = CGSize(width: 900, height: 700)
        #expect(CameraViewerLayout.usesSplit(window: Self.tabletLandscape, isRegularWidth: true, container: wide))
        #expect(!CameraViewerLayout.usesSplit(window: Self.tabletLandscape, isRegularWidth: true, container: CGSize(width: 600, height: 700)))
        #expect(!CameraViewerLayout.usesSplit(window: CGSize(width: 834, height: 1210), isRegularWidth: true, container: wide),
                "iPad portrait stays stacked")
        #expect(!CameraViewerLayout.usesSplit(window: Self.phone, isRegularWidth: false, container: Self.phone))
    }

    @Test func tileReadsLiveOrSnapshot() {
        var state = CameraStreamState(modes: [.webRTC])
        #expect(CameraTile.statusText(state) == "Snapshot")
        state.firstFrame(.webRTC)
        #expect(CameraTile.statusText(state) == "Live")
    }

    // MARK: Renders

    private func render(_ view: some View, size: CGSize, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "input_boolean.is_front_door_recording", state: "on", attributes: [:])])
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let content = view
            .environment(connection(store))
            .environment(store)
            .environment(\.cameraStreamPool, pool)
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    @Test(arguments: HomeConfig.cameras)
    func viewerRendersStackedSplitAndLarge(camera: HomeConfig.Camera) {
        #expect(render(CameraViewer(camera: camera, caller: NullCaller()), size: Self.phone) != nil)
        #expect(render(CameraViewer(camera: camera), size: Self.phone, typeSize: .accessibility5) != nil)
        #expect(render(CameraViewer(camera: camera), size: Self.tabletLandscape) != nil)
    }

    @Test func controlsRenderInBothAxesAndEveryState() {
        let model = CameraLiveModel(camera: HomeConfig.cameras[0], modes: [])
        for axis in [Axis.horizontal, .vertical] {
            for recording in [false, true] {
                let controls = CameraControls(camera: HomeConfig.cameras[0], model: model, caller: NullCaller(),
                                              isRecording: recording, axis: axis)
                #expect(render(controls, size: CGSize(width: 402, height: 400)) != nil)
            }
        }
        model.setMuted(false)
        let unmuted = CameraControls(camera: HomeConfig.cameras[1], model: model, caller: NullCaller(), isRecording: false, axis: .horizontal)
        #expect(render(unmuted, size: CGSize(width: 402, height: 400), typeSize: .accessibility5) != nil)
    }

    @Test func controlButtonsRenderActiveAndIdle() {
        for active in [false, true] {
            let button = CameraControlButton(title: "Record", symbol: "record.circle", isActive: active, tint: .red,
                                             pulses: active, accessibilityLabel: "Record", accessibilityValue: "",
                                             isToggle: true, identifier: "test") {}
            #expect(render(button, size: CGSize(width: 140, height: 120)) != nil)
        }
    }

    @Test func gridAndTilesRender() {
        #expect(render(CameraGrid { _ in }, size: Self.phone) != nil)
        #expect(render(CameraTile(camera: HomeConfig.cameras[1]), size: CGSize(width: 200, height: 120)) != nil)
        #expect(render(CameraLiveView(camera: HomeConfig.cameras[1], style: .tile), size: CGSize(width: 200, height: 120)) != nil)
    }
}
