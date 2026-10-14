import CoreGraphics
import Foundation
import HassCore
@testable import HassUI
import ImageIO
import SwiftUI
import Testing

/// The blurred house photo behind every page (pattern: `.agents/patterns/page-backdrop.md`).
@MainActor
struct HouseBackdropTests {
    private let server = HassServer(baseURL: URL(string: "https://ha.example.com/lovelace?x=1")!)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "backdrop-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A small photo to stand in for the server's WebP.
    private func photo(red: Double) -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        return context.makeImage()!
    }

    /// A pipeline stub that yields `images` and finishes, counting how often it was asked.
    private func stream(_ images: [CGImage], counter: Counter? = nil) -> @Sendable (URL) -> AsyncStream<CGImage> {
        let boxed = UncheckedImages(images)
        return { _ in
            AsyncStream { continuation in
                Task {
                    await counter?.increment()
                    for image in boxed.images { continuation.yield(image) }
                    continuation.finish()
                }
            }
        }
    }

    @Test func photoComesFromTheServersPublicFolder() {
        #expect(HouseBackdropStore.imageURL(for: server).absoluteString == "https://ha.example.com/local/images/house.webp")
    }

    @Test func renderKeepsTheSize() throws {
        let render = try #require(HouseBackdropStore.render(photo(red: 0.8)))
        #expect(render.width == 64 && render.height == 48)
    }

    @Test func refreshCachesTheRenderForTheNextLaunch() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HouseBackdropStore(server: server, directory: folder, photos: stream([photo(red: 0.6)]))
        #expect(store.image == nil)
        await store.refresh()
        #expect(store.image != nil)
        // A new launch reads the cached render synchronously, before the pipeline answers.
        let relaunch = HouseBackdropStore(server: server, directory: folder, photos: stream([]))
        #expect(relaunch.image != nil)
        await relaunch.refresh()
        #expect(relaunch.image != nil)
    }

    @Test func refreshRunsOncePerStoreAndTakesTheNewestPhoto() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let counter = Counter()
        let wide = try #require(CGContext(data: nil, width: 96, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let store = HouseBackdropStore(server: server, directory: folder, photos: stream([photo(red: 0.3), wide], counter: counter))
        await store.refresh()
        await store.refresh()
        #expect(await counter.value == 1)
        #expect(store.image?.width == 96)
    }

    @Test func backdropRendersWithAndWithoutAPhoto() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = HouseBackdropStore(server: server, directory: folder, photos: stream([]))
        let lit = HouseBackdropStore(server: server, directory: folder, photos: stream([photo(red: 0.9)]))
        await lit.refresh()
        for store in [empty, lit] {
            let view = HouseBackdrop()
                .environment(store)
                .environment(\.backdropCanvas, CGSize(width: 390, height: 844))
                .frame(width: 390, height: 844)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
    }

    @Test func refreshRemovesRendersFromOlderRecipes() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appending(path: "house-blurred.png")
        FileManager.default.createFile(atPath: old.path, contents: Data([1]))
        let store = HouseBackdropStore(server: server, directory: folder, photos: stream([]))
        await store.refresh()
        for _ in 0..<40 where FileManager.default.fileExists(atPath: old.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func scrimFollowsDirectionG() {
        // 0.36 → 0.18 (28%) → 0.36 (50%) → 0.50 → 0.64, darkest at the bottom behind the tab bar.
        let stops = HouseBackdropStyle.scrimStops
        #expect(stops.map(\.location) == [0, 0.28, 0.50, 0.75, 1])
        #expect(HouseBackdropStyle.scale == 1.06)
        #expect(HouseBackdropStore.blurRadius == 20)
        #expect(HouseBackdropStore.saturation == 1.1)
    }
}

/// CGImage is immutable; this carries the stub's images into the stream task.
private struct UncheckedImages: @unchecked Sendable {
    let images: [CGImage]
    init(_ images: [CGImage]) { self.images = images }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
