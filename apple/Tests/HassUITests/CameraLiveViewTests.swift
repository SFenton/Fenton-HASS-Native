import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

@MainActor
struct CameraLiveViewTests {
    @Test func badgeAndVoiceOverTextFollowThePhase() {
        var state = CameraStreamState()
        #expect(CameraLiveView.badgeText(state) == "Connecting")
        #expect(CameraLiveView.statusText(state) == "Connecting to live video")
        state.firstFrame(.webRTC)
        #expect(CameraLiveView.badgeText(state) == "Live")
        #expect(CameraLiveView.statusText(state) == "Live")
        state.failed(.webRTC)
        state.firstFrame(.hls)
        #expect(CameraLiveView.badgeText(state) == "Live · Delayed")
        #expect(CameraLiveView.statusText(state) == "Live, a few seconds behind")
        state.failed(.hls)
        #expect(CameraLiveView.badgeText(state) == "Snapshot")
        #expect(CameraLiveView.statusText(state) == "Live video unavailable, showing the latest snapshot")
        #expect(CameraLiveView.statusText(CameraStreamState(modes: [])) == "Latest snapshot")
    }

    @Test func modelWithoutModesFailsToTheSnapshot() {
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let model = CameraLiveModel(camera: HomeConfig.cameras[0], modes: [])
        model.start(connection: connection)
        #expect(model.state.phase == .failed)
        #expect(model.hlsPlayer == nil)
        model.stop()
    }

    @Test func staleFirstFrameIsIgnored() {
        let model = CameraLiveModel(camera: HomeConfig.cameras[0], modes: [.webRTC, .hls])
        model.firstFrame(.hls)
        #expect(model.state.phase == .connecting)
        model.firstFrame(.webRTC)
        #expect(model.state.phase == .live)
    }

    /// A first frame that lands after the timeout's timer fired, but before its continuation ran (the main actor
    /// was busy), keeps the stream live instead of failing it over to the next mode.
    @Test func aFirstFrameBeatsATimeoutThatHasNotRunYet() async {
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        var opens = 0
        let model = CameraLiveModel(camera: HomeConfig.cameras[0], modes: [.webRTC, .hls],
                                    opener: { _, _, _, _ in opens += 1 }, firstFrameTimeout: { _ in .milliseconds(20) })
        model.start(connection: connection)
        for _ in 0..<300 where opens == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(opens == 1)
        holdMainActor(0.2) // Past the timeout, as a long frame or another suite's work does.
        model.firstFrame(.webRTC)
        #expect(model.state.phase == .live)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.state.phase == .live)
        #expect(model.state.mode == .webRTC)
        #expect(opens == 1, "No fallback to HLS")
        model.stop()
    }

    /// Blocks the main actor without yielding (synchronous, so async code may call it).
    private func holdMainActor(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Hosted render of the viewer from a snapshot-only store: the snapshot and badge draw with no stream.
    @Test func viewerRendersWithoutAStream() {
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let view = CameraViewer(camera: HomeConfig.cameras[0])
            .environment(connection)
            .environment(store)
            .frame(width: 402, height: 874)
        #expect(ImageRenderer(content: view).cgImage != nil)
    }
}
