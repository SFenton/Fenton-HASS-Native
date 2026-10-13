import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// The media remote's artwork prefetch, which holds its ``ContentGate`` until every app's artwork has loaded.
struct RemoteArtworkTests {
    private func pipeline() -> ImagePipeline {
        ImagePipeline(directory: FileManager.default.temporaryDirectory.appending(path: "remote-artwork-\(UUID().uuidString)"))
    }

    @MainActor @Test func artworkCoversEveryAppAcrossTabs() {
        #expect(MediaRemoteSheet.artworkURLs(MediaRemotes.livingRoomShield, server: nil).isEmpty)
        let urls = MediaRemoteSheet.artworkURLs(MediaRemotes.livingRoomShield, server: .fentonHome)
        #expect(urls.count == MediaRemotes.livingRoomShield.apps.filter { $0.imagePath != nil }.count)
        #expect(MediaRemoteSheet.artworkPixels == 512)
    }

    @Test func prefetchReturnsAtOnceWithNothingToLoad() async {
        let start = ContinuousClock.now
        await MediaRemoteSheet.prefetch([], pipeline: pipeline(), timeout: .seconds(30))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    /// An image that never answers stops holding the sheet at the timeout.
    @Test func prefetchStopsWaitingAtTheTimeout() async {
        let urls = [URL(string: "http://10.255.255.1/never.png")!] // Non-routable: the request hangs.
        let start = ContinuousClock.now
        let images = pipeline()
        await MediaRemoteSheet.prefetch(urls, pipeline: images, timeout: .milliseconds(100))
        // Off the main actor, so busy hosted renders can't delay it; the request itself waits far longer.
        #expect(ContinuousClock.now - start < .seconds(30))
        #expect(images.memoryImage(for: urls[0]) == nil, "It returned while the image was still loading")
    }

    @MainActor @Test func sheetRendersBehindItsGateWhileArtworkLoads() {
        let store = EntityStore()
        store.replaceAll(MediaRemoteFixtures.states)
        let controller = MediaRemoteController(config: MediaRemotes.livingRoomShield, store: store, caller: NullCaller())
        let sheet = MediaRemoteSheet(controller: controller, imageServer: .fentonHome, initialTab: .apps, pipeline: pipeline())
            .frame(width: 402, height: 874)
        #expect(ImageRenderer(content: sheet).cgImage != nil)
    }
}
