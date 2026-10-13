import CoreGraphics
import Foundation
import HassCore
@testable import HassUI
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// The blurred house photo behind every page (pattern: `.agents/patterns/page-backdrop.md`).
@MainActor
struct HouseBackdropTests {
    private let server = HassServer(baseURL: URL(string: "https://ha.example.com/lovelace?x=1")!)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "backdrop-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A small PNG to stand in for the server's WebP.
    private func photo(red: Double) -> Data {
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func photoComesFromTheServersPublicFolder() {
        #expect(HouseBackdropStore.imageURL(for: server).absoluteString == "https://ha.example.com/local/images/house.webp")
    }

    @Test func renderKeepsTheSizeAndRejectsNonImages() throws {
        let render = try #require(HouseBackdropStore.render(photo(red: 0.8)))
        #expect(render.width == 64 && render.height == 48)
        #expect(HouseBackdropStore.render(Data("not an image".utf8)) == nil)
    }

    @Test func refreshCachesTheRenderForTheNextLaunch() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = photo(red: 0.6)
        let store = HouseBackdropStore(server: server, directory: folder) { _ in data }
        #expect(store.image == nil)
        await store.refresh()
        #expect(store.image != nil)
        // A new launch reads the cached render synchronously, before any network work.
        let relaunch = HouseBackdropStore(server: server, directory: folder) { _ in throw URLError(.notConnectedToInternet) }
        #expect(relaunch.image != nil)
        await relaunch.refresh()
        #expect(relaunch.image != nil)
    }

    @Test func refreshRunsOncePerLaunchAndKeepsTheCacheOnFailure() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let counter = Counter()
        let data = photo(red: 0.3)
        let store = HouseBackdropStore(server: server, directory: folder) { _ in
            await counter.increment()
            return data
        }
        await store.refresh()
        await store.refresh()
        #expect(await counter.value == 1)
        let failing = HouseBackdropStore(server: server, directory: folder) { _ in Data() }
        await failing.refresh()
        #expect(failing.image != nil)
    }

    @Test func backdropRendersInBothSchemes() {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HouseBackdropStore(server: server, directory: folder) { _ in Data() }
        for scheme in [ColorScheme.dark, .light] {
            let view = HouseBackdrop()
                .environment(store)
                .environment(\.backdropCanvas, CGSize(width: 390, height: 844))
                .environment(\.colorScheme, scheme)
                .frame(width: 390, height: 844)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
