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
