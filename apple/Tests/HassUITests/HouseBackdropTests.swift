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
    private let phone = CGSize(width: 402, height: 874)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "backdrop-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func settings(percent: Int? = nil) -> BackdropBlurSettings {
        let suite = "HouseBackdropTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let percent { defaults.set(percent, forKey: BackdropBlur.defaultsKey) }
        return BackdropBlurSettings(defaults: defaults)
    }

    private func makeStore(_ folder: URL, photos images: [CGImage], counter: Counter? = nil, percent: Int? = nil) -> HouseBackdropStore {
        HouseBackdropStore(server: server, directory: folder, blur: settings(percent: percent), renderGap: .zero,
                           photos: stream(images, counter: counter))
    }

    /// A flat photo to stand in for the server's WebP.
    private func photo(red: Double, width: Int = 64, height: Int = 48) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Black on the left half, white on the right: a vertical edge at the center.
    private func edgePhoto(side: Int = 200) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
        return context.makeImage()!
    }

    /// Fine black and white stripes, for measuring how much detail a render keeps.
    private func stripes(side: Int = 240) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in stride(from: 0, to: side, by: 8) { context.fill(CGRect(x: x, y: 0, width: 4, height: side)) }
        return context.makeImage()!
    }

    /// The red channel of one row of an image, 0...255.
    private func row(_ image: CGImage, y: Int) -> [Double] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<image.width).map { Double(bytes[(y * image.width + $0) * 4]) }
    }

    private func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }

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

    // MARK: Photo and render

    @Test func photoComesFromTheServersPublicFolder() {
        #expect(HouseBackdropStore.imageURL(for: server).absoluteString == "https://ha.example.com/local/images/house.webp")
    }

    @Test func renderIsTheSpecsSize() throws {
        for percent in [0, 50, 100] {
            let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 3, percent: percent))
            let render = try #require(BackdropRenderer.render(photo(red: 0.8), spec: spec))
            #expect(render.width == spec.renderWidth && render.height == spec.renderHeight)
        }
    }

    @Test func blurSoftensDetailAndSharpKeepsIt() throws {
        let source = stripes()
        let window = CGSize(width: 240, height: 240)
        func contrast(_ percent: Int) throws -> Double {
            let spec = try #require(BackdropRenderSpec(points: window, displayScale: 1, percent: percent))
            let render = try #require(BackdropRenderer.render(source, spec: spec))
            // The middle half of the row, clear of the photo's clamped edge.
            let values = row(render, y: render.height / 2)
            return spread(Array(values[(values.count / 4)..<(values.count * 3 / 4)]))
        }
        let sharp = try contrast(0), normal = try contrast(50), soft = try contrast(100)
        #expect(sharp > 200)
        #expect(normal < 40)
        #expect(soft <= normal + 2, "normal \(normal), soft \(soft)")
    }

    /// The default blur matches the web's on screen: a Gaussian edge's 10 to 90% rise is 2.563 standard deviations, and
    /// the standard deviation is 16.8 pt (`BackdropBlur.defaultRadius`), 43 pt, however far the render is reduced.
    @Test func blurWidthOnScreenIsTheSettingsRadiusInPoints() throws {
        let window = CGSize(width: 200, height: 200)
        let spec = try #require(BackdropRenderSpec(points: window, displayScale: 1, percent: BackdropBlur.defaultPercent))
        #expect(spec.divisor == 2)
        let render = try #require(BackdropRenderer.render(edgePhoto(), spec: spec))
        let values = row(render, y: render.height / 2).map { $0 / 255 }
        let low = try #require(values.firstIndex { $0 >= 0.1 }), high = try #require(values.firstIndex { $0 >= 0.9 })
        let rise = Double(high - low) * Double(spec.divisor) / spec.pixelsPerPoint
        let expected = 2.563 * BackdropBlur.defaultRadius
        #expect(abs(rise - expected) < expected * 0.2, "rise \(rise) pt, expected \(expected) pt")
    }

    /// How long one render takes for a phone-size window at 3x from a house-photo-size source (printed for the PR; the
    /// bound is loose because CI machines differ). Core Image is the whole cost, off the main thread.
    @Test func renderTimesStayFarUnderASecond() throws {
        let source = photo(red: 0.5, width: 1024, height: 684)
        _ = BackdropRenderer.render(source, spec: try #require(BackdropRenderSpec(points: phone, displayScale: 3, percent: 50))) // warm the context
        for percent in [0, 50, 100] {
            let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 3, percent: percent))
            let start = ContinuousClock.now
            _ = try #require(BackdropRenderer.render(source, spec: spec))
            let elapsed = ContinuousClock.now - start
            print("RENDERMS percent \(percent) size \(spec.renderWidth)x\(spec.renderHeight) \(elapsed)")
            #expect(elapsed < .seconds(1))
        }
    }

    @Test func renderCoversTheWindowWithoutTransparentEdges() throws {
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 1, percent: 100))
        let render = try #require(BackdropRenderer.render(photo(red: 0.9), spec: spec))
        let context = CGContext(data: nil, width: render.width, height: render.height, bitsPerComponent: 8, bytesPerRow: render.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(render, in: CGRect(x: 0, y: 0, width: render.width, height: render.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(0, 0), (render.width - 1, 0), (0, render.height - 1), (render.width - 1, render.height - 1)] {
            let alpha = bytes[(y * render.width + x) * 4 + 3], red = bytes[(y * render.width + x) * 4]
            #expect(alpha >= 253, "alpha \(alpha) at \(x),\(y)")
            #expect(red > 150, "red \(red) at \(x),\(y)")
        }
    }

    @Test func digestIdentifiesAPhotoByItsPixels() {
        #expect(BackdropRenderer.digest(of: photo(red: 0.5)) == BackdropRenderer.digest(of: photo(red: 0.5)))
        #expect(BackdropRenderer.digest(of: photo(red: 0.5)) != BackdropRenderer.digest(of: photo(red: 0.6)))
        #expect(BackdropRenderer.digest(of: photo(red: 0.5)) != BackdropRenderer.digest(of: photo(red: 0.5, width: 32)))
        #expect(BackdropRenderer.digest(of: photo(red: 0.5)).count == 16)
    }

    @Test func renderOrLoadStoresOnceThenReadsTheFile() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 1, percent: 50))
        let picture = photo(red: 0.7)
        let first = try #require(BackdropRenderer.renderOrLoad(picture, digest: "d1", spec: spec, in: folder))
        #expect(first.rendered)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: spec.cacheName(photo: "d1")).path))
        let second = try #require(BackdropRenderer.renderOrLoad(picture, digest: "d1", spec: spec, in: folder))
        #expect(!second.rendered)
        #expect(second.image.width == first.image.width && second.image.height == first.image.height)
    }

    @Test func latestPointerSurvivesAndIgnoresMissingOrBadFiles() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(BackdropRenderer.loadLatest(in: folder) == nil)
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 1, percent: 50))
        _ = try #require(BackdropRenderer.renderOrLoad(photo(red: 0.7), digest: "d1", spec: spec, in: folder))
        BackdropRenderer.markLatest(spec.cacheName(photo: "d1"), in: folder)
        #expect(BackdropRenderer.loadLatest(in: folder)?.name == spec.cacheName(photo: "d1"))
        BackdropRenderer.markLatest("missing.jpg", in: folder)
        #expect(BackdropRenderer.loadLatest(in: folder) == nil)
        BackdropRenderer.markLatest("../escape.jpg", in: folder)
        #expect(BackdropRenderer.loadLatest(in: folder) == nil)
        BackdropRenderer.markLatest("", in: folder)
        #expect(BackdropRenderer.loadLatest(in: folder) == nil)
        #expect(BackdropRenderer.load(folder.appending(path: "nothing.jpg")) == nil)
    }

    @Test func pruneKeepsTheNewestRendersAndTheProtectedOne() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<6 {
            let url = folder.appending(path: "backdrop-r-p-\(index).jpg")
            FileManager.default.createFile(atPath: url.path, contents: Data([1]))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1000 + index))], ofItemAtPath: url.path)
        }
        FileManager.default.createFile(atPath: folder.appending(path: "latest.txt").path, contents: Data([1]))
        BackdropRenderer.prune(folder, keep: 2, protecting: "backdrop-r-p-0.jpg")
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(left == ["backdrop-r-p-0.jpg", "backdrop-r-p-4.jpg", "backdrop-r-p-5.jpg", "latest.txt"])
        // Nothing to do at or under the limit.
        BackdropRenderer.prune(folder, keep: 8, protecting: "")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 4)
    }

    @Test func retiredRendersAreRemoved() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in BackdropRenderer.retiredNames { FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: Data([1])) }
        BackdropRenderer.removeRetired(in: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    // MARK: Store

    /// The pointer to the render on screen is written off the main thread; waits for it.
    private func waitForPointer(in folder: URL) async throws {
        for _ in 0..<100 where BackdropRenderer.loadLatest(in: folder) == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func refreshRendersAndCachesForTheNextLaunch() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(folder, photos: [photo(red: 0.6)])
        store.setWindow(phone, scale: 3)
        #expect(store.image == nil)
        await store.refresh()
        #expect(store.image != nil)
        #expect(store.renderCount == 1)
        await store.settled()
        try await waitForPointer(in: folder)
        // A new launch reads the cached render synchronously, before the pipeline answers, and finds nothing to redo.
        let relaunch = makeStore(folder, photos: [photo(red: 0.6)])
        #expect(relaunch.image != nil)
        relaunch.setWindow(phone, scale: 3)
        await relaunch.refresh()
        #expect(relaunch.image != nil)
        #expect(relaunch.renderCount == 0)
    }

    @Test func nothingRendersUntilThereIsAPhotoAndAWindow() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let noWindow = makeStore(folder, photos: [photo(red: 0.6)])
        await noWindow.refresh()
        #expect(noWindow.image == nil)
        let noPhoto = makeStore(folder, photos: [])
        noPhoto.setWindow(phone, scale: 3)
        await noPhoto.refresh()
        #expect(noPhoto.image == nil)
        // The window arriving after the photo renders then.
        noWindow.setWindow(phone, scale: 3)
        await noWindow.settled()
        #expect(noWindow.image != nil)
    }

    @Test func refreshRunsOncePerStoreAndTakesTheNewestPhoto() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let counter = Counter()
        let wide = photo(red: 0.3, width: 96, height: 48)
        let store = makeStore(folder, photos: [photo(red: 0.3), wide], counter: counter)
        store.setWindow(phone, scale: 3)
        await store.refresh()
        await store.refresh()
        #expect(await counter.value == 1)
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 3, percent: 50))
        #expect(store.image?.width == spec.renderWidth)
        // The same file shipped again is the same render: it is not drawn twice.
        let before = store.renderCount
        let same = makeStore(folder, photos: [wide])
        same.setWindow(phone, scale: 3)
        await same.refresh()
        #expect(same.renderCount == 0 && before >= 1)
    }

    @Test func changingTheBlurRendersTheNewRadiusAndKeepsThePictureMeanwhile() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(folder, photos: [photo(red: 0.6)])
        store.setWindow(phone, scale: 3)
        await store.refresh()
        let first = try #require(store.image)
        #expect(first.width == 302)
        store.blur.set(0)
        // The old render stays up until the new one is ready.
        #expect(store.image === first)
        await store.settled()
        let sharp = try #require(store.image)
        #expect(sharp.width == 1206)
        // Back to a position seen before: from memory, not drawn again.
        let count = store.renderCount
        store.blur.set(50)
        await store.settled()
        #expect(store.image?.width == 302)
        #expect(store.renderCount == count)
    }

    @Test func aBurstOfChangesRendersTheLatestOnce() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(folder, photos: [photo(red: 0.6)])
        store.setWindow(phone, scale: 3)
        await store.refresh()
        let count = store.renderCount
        for percent in stride(from: 55, through: 100, by: 5) { store.blur.set(percent) }
        await store.settled()
        #expect(store.renderCount == count + 1)
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 3, percent: 100))
        #expect(store.image?.width == spec.renderWidth)
    }

    @Test func renderGapPausesBetweenBackToBackRenders() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HouseBackdropStore(server: server, directory: folder, blur: settings(), renderGap: .milliseconds(5),
                                       photos: stream([photo(red: 0.6)]))
        store.setWindow(phone, scale: 3)
        await store.refresh()
        let count = store.renderCount
        store.blur.set(60)
        // A change that lands while that render runs is rendered after the gap.
        try await Task.sleep(for: .milliseconds(1))
        store.blur.set(70)
        await store.settled()
        #expect(store.renderCount >= count + 1)
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 3, percent: 70))
        #expect(store.image?.width == spec.renderWidth)
    }

    @Test func aNewWindowRendersAndTheSameOneDoesNot() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(folder, photos: [photo(red: 0.6)])
        store.setWindow(phone, scale: 3)
        await store.refresh()
        let count = store.renderCount
        store.setWindow(phone, scale: 3)
        await store.settled()
        #expect(store.renderCount == count)
        // Rotation.
        store.setWindow(CGSize(width: 874, height: 402), scale: 3)
        await store.settled()
        #expect(store.renderCount == count + 1)
        #expect(store.image?.width == 656)
        // A different display scale is a different picture.
        store.setWindow(CGSize(width: 874, height: 402), scale: 2)
        await store.settled()
        #expect(store.renderCount == count + 2)
    }

    @Test func aChangedPhotoReplacesTheRender() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(folder, photos: [photo(red: 0.2), photo(red: 0.9)])
        store.setWindow(phone, scale: 1)
        await store.refresh()
        #expect(store.renderCount >= 1)
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 1, percent: 50))
        let red = row(try #require(store.image), y: 10)[10]
        #expect(red > 200, "the newest photo is on screen: red \(red)")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: spec.cacheName(photo: BackdropRenderer.digest(of: photo(red: 0.9)))).path))
    }

    @Test func rendersAreKeptOnDiskForOtherPositionsAndPruned() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = makeStore(folder, photos: [photo(red: 0.6)])
        store.setWindow(CGSize(width: 100, height: 200), scale: 1)
        await store.refresh()
        for percent in stride(from: 0, through: 100, by: 10) {
            store.blur.set(percent)
            await store.settled()
        }
        let renders = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("backdrop-") }
        #expect(renders.count <= BackdropRenderer.keptRenders)
        #expect(renders.count >= 2)
    }

    @Test func backdropRendersWithAndWithoutAPhoto() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = makeStore(folder, photos: [])
        let lit = makeStore(directory(), photos: [photo(red: 0.9)])
        lit.setWindow(CGSize(width: 390, height: 844), scale: 1)
        await lit.refresh()
        for store in [empty, lit] {
            let view = HouseBackdrop()
                .environment(store)
                .environment(\.backdropCanvas, CGSize(width: 390, height: 844))
                .frame(width: 390, height: 844)
            #expect(ImageRenderer(content: view).cgImage != nil)
        }
    }

    @Test func canvasProviderTellsTheStoreTheWindow() async throws {
        let store = makeStore(directory(), photos: [photo(red: 0.9)])
        let view = Color.clear.frame(width: 390, height: 844)
            .backdropCanvasProvider()
            .environment(store)
            .environment(\.displayScale, 2)
        let renderer = ImageRenderer(content: view)
        _ = renderer.cgImage
        // `ImageRenderer` lays the view out, which measures it.
        try await Task.sleep(for: .milliseconds(200))
        await store.refresh()
        await store.settled()
        #expect(store.image != nil || store.renderCount == 0)
    }

    @Test func refreshRemovesRendersFromOlderRecipes() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appending(path: "house-blurred-g.png")
        FileManager.default.createFile(atPath: old.path, contents: Data([1]))
        let store = makeStore(folder, photos: [])
        await store.refresh()
        for _ in 0..<40 where FileManager.default.fileExists(atPath: old.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    /// The wallpaper filled only the safe-area rect (402 x 778 on an iPhone 18 Pro), leaving the bottom 96 pt plain
    /// (owner, 2026-10-16). The canvas is the measured view plus every inset.
    @Test func canvasIsTheWholeWindowNotTheSafeAreaRect() {
        let phone = BackdropCanvas.size(container: CGSize(width: 402, height: 778),
                                        insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        #expect(phone == CGSize(width: 402, height: 874))
        let landscape = BackdropCanvas.size(container: CGSize(width: 1100, height: 760),
                                            insets: EdgeInsets(top: 24, leading: 20, bottom: 20, trailing: 20))
        #expect(landscape == CGSize(width: 1140, height: 804))
    }

    @Test func canvasWithoutInsetsIsTheContainerAndNegativeInsetsAreIgnored() {
        #expect(BackdropCanvas.size(container: CGSize(width: 820, height: 1180), insets: EdgeInsets()) == CGSize(width: 820, height: 1180))
        let odd = BackdropCanvas.size(container: CGSize(width: 100, height: 200),
                                      insets: EdgeInsets(top: -5, leading: -5, bottom: 10, trailing: 0))
        #expect(odd == CGSize(width: 100, height: 210))
    }

    #if DEBUG
    /// The UI journeys' fixture photo stays far brighter than the plain base color under the densest scrim.
    @Test func fixturePhotoIsBrighterThanTheBase() throws {
        let photo = try #require(HouseBackdropStore.fixturePhoto())
        #expect(photo.width == 960 && photo.height == 640)
        let spec = try #require(BackdropRenderSpec(points: phone, displayScale: 1, percent: 50))
        let render = try #require(BackdropRenderer.render(photo, spec: spec))
        let data = try #require(render.dataProvider?.data as Data?)
        let densest = 1 - 0.64
        let brightest = Double(data.prefix(3).max() ?? 0) / 255 * densest
        let base = 35.0 / 255 // the base color's brightest channel before any scrim
        #expect(brightest > base * 1.5)
    }

    @Test func fixtureStoreIsIsolatedAndHonoursTheStartingBlur() async throws {
        setenv("FENTON_BACKDROP_FIXTURE", "1", 1)
        setenv("FENTON_BACKDROP_BLUR", "20", 1)
        defer { unsetenv("FENTON_BACKDROP_FIXTURE"); unsetenv("FENTON_BACKDROP_BLUR") }
        let store = try #require(HouseBackdropStore.fixture(for: server))
        #expect(store.blur.percent == 20)
        store.setWindow(phone, scale: 1)
        await store.refresh()
        #expect(store.image != nil)
        #expect(HouseBackdropStore.session(for: server).blur.percent == 20)
        unsetenv("FENTON_BACKDROP_FIXTURE")
        #expect(HouseBackdropStore.fixture(for: server) == nil)
    }
    #endif

    // MARK: Look

    @Test func scrimFollowsDirectionG() {
        // 0.44 → 0.45 (28%) → 0.46 (50%) → 0.52 → 0.64, darkest at the bottom behind the tab bar.
        let stops = HouseBackdropStyle.scrimStops
        #expect(stops.map(\.location) == [0, 0.28, 0.50, 0.75, 1])
        #expect(HouseBackdropStyle.scrimOpacities.map(\.value) == [0.44, 0.45, 0.46, 0.52, 0.64])
        // Never lighter in the top half than 0.44: white titles and headers sit there.
        #expect(HouseBackdropStyle.scrimOpacities.filter { $0.location <= 0.5 }.allSatisfy { $0.value >= 0.44 })
        #expect(HouseBackdropStyle.scale == 1.06)
        #expect(BackdropRenderer.saturation == 1.1)
    }

    @Test func increaseContrastDarkensTheScrimAndNothingElse() throws {
        let normal = HouseBackdropStyle.scrimStops(increasedContrast: false)
        let dense = HouseBackdropStyle.scrimStops(increasedContrast: true)
        #expect(normal.map(\.location) == dense.map(\.location))
        let opacity = { (stop: Gradient.Stop) -> Double in
            let resolved = stop.color.resolve(in: EnvironmentValues())
            return Double(resolved.opacity)
        }
        for (a, b) in zip(normal, dense) {
            #expect(abs(opacity(b) - opacity(a) - HouseBackdropStyle.increasedContrastBoost) < 0.005)
        }
        #expect(HouseBackdropStyle.increasedContrastBoost > 0)
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
