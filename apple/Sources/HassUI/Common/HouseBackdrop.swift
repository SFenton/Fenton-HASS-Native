import CoreImage
import HassCore
import HassDesign
import ImageIO
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Store

/// The blurred photo of the house behind every page (web `AppShell.module.css` `.backdrop`: the image served by
/// Home Assistant at `/local/images/house.webp`; pattern: `.agents/patterns/page-backdrop.md`).
///
/// No reload on reopen: the blurred render is cached on disk and read synchronously at launch, so the first
/// frame already shows it. ``refresh()`` downloads the original once per launch and replaces the render only
/// when the bytes changed.
@MainActor
@Observable
final class HouseBackdropStore {
    /// The blurred render, once known.
    private(set) var image: CGImage?

    @ObservationIgnored private let source: URL
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private var refreshed = false

    /// Creates the store and loads the cached render.
    /// - Parameters:
    ///   - server: The signed-in server, which serves the photo.
    ///   - directory: Where the original and its render are cached.
    ///   - fetch: Downloads the photo (tests pass a stub).
    init(server: HassServer, directory: URL = HouseBackdropStore.defaultDirectory,
         fetch: @escaping @Sendable (URL) async throws -> Data = HouseBackdropStore.download) {
        source = Self.imageURL(for: server)
        self.directory = directory
        self.fetch = fetch
        image = Self.loadImage(at: directory.appending(path: Self.renderName))
    }

    /// Downloads the photo once per store and swaps in a new render when it changed. Failures keep the cache.
    func refresh() async {
        guard !refreshed else { return }
        refreshed = true
        guard let data = try? await fetch(source), !data.isEmpty else { return }
        let originalURL = directory.appending(path: Self.originalName)
        if image != nil, (try? Data(contentsOf: originalURL)) == data { return }
        let renderURL = directory.appending(path: Self.renderName)
        let directory = directory
        let rendered: CGImage? = await Task.detached(priority: .utility) {
            guard let render = Self.render(data) else { return nil }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: originalURL, options: .atomic)
            Self.write(render, to: renderURL)
            return render
        }.value
        if let rendered { image = rendered }
    }

    // MARK: Pure helpers

    /// The original's file name in the cache.
    nonisolated static let originalName = "house.webp"
    /// The blurred render's file name in the cache.
    nonisolated static let renderName = "house-blurred.png"
    /// Width the photo is reduced to before blurring; the blur hides the lost detail.
    nonisolated static let renderWidth: CGFloat = 480
    /// Blur radius at ``renderWidth`` (web `blur(16px)` over a phone-width viewport, about 400 px).
    nonisolated static let blurRadius: Double = 18

    /// `<server>/local/images/house.webp`, Home Assistant's public `www` folder (no sign-in needed).
    nonisolated static func imageURL(for server: HassServer) -> URL {
        server.baseURL.appending(path: "local/images/house.webp")
    }

    /// The cache folder: Caches/HouseBackdrop.
    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "HouseBackdrop", directoryHint: .isDirectory)
    }

    /// Downloads `url`, failing on any non-2xx status.
    nonisolated static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Decodes, downsizes, saturates (web `saturate(1.04)`) and blurs the photo. Brightness is left to the
    /// view, which darkens it in dark mode and washes it in light mode.
    /// - Parameter data: Encoded image (WebP, JPEG or PNG).
    /// - Returns: The render, or nil when the data is not an image.
    nonisolated static func render(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var image = CIImage(cgImage: original)
        let scale = min(1, renderWidth / max(1, image.extent.width))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        image = image.clampedToExtent()
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.04])
            .applyingGaussianBlur(sigma: blurRadius)
            .cropped(to: extent)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: extent)
    }

    /// Reads a cached render.
    nonisolated static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Writes a render as PNG.
    nonisolated static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

// MARK: - View

/// The page background: the house photo, blurred and dimmed like the web (`.backdrop` and `.scrim` in
/// `AppShell.module.css`), drawn once per page by `pageChrome()`. Modals have none.
///
/// Every page shows the same crop: the photo fills the window (``EnvironmentValues/backdropCanvas``) and each
/// page, split pane included, shows the part of it under its own frame, so a split reads as one picture.
/// Reduce Transparency draws the plain background instead.
struct HouseBackdrop: View {
    @Environment(HouseBackdropStore.self) private var store: HouseBackdropStore?
    @Environment(\.backdropCanvas) private var canvas
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var origin: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HouseBackdropStyle.base(colorScheme)
                if let image = store?.image, !reduceTransparency {
                    let size = canvas == .zero ? proxy.size : canvas
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(1.05)
                        .offset(x: -origin.x, y: -origin.y)
                        .transition(.opacity)
                    HouseBackdropStyle.scrim(colorScheme)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: store?.image != nil)
    }
}

/// Colors of the backdrop's layers.
enum HouseBackdropStyle {
    /// Under the photo: the web shell's `#111723` in dark mode, the grouped background in light mode.
    static func base(_ scheme: ColorScheme) -> Color {
        #if canImport(UIKit)
        scheme == .dark ? Color(red: 17 / 255, green: 23 / 255, blue: 35 / 255) : Color(uiColor: .systemGroupedBackground)
        #else
        scheme == .dark ? Color(red: 17 / 255, green: 23 / 255, blue: 35 / 255) : Color.white
        #endif
    }

    /// Over the photo. Dark mode is the web's `brightness(0.76)` plus its scrim (`rgba(3,6,10,0.08)` to
    /// `rgba(3,6,10,0.42)` over `rgba(6,10,16,0.12)`). Light mode, which the web lacks, washes the photo
    /// toward white (38 → 52%) so dark text on it keeps its contrast.
    @ViewBuilder
    static func scrim(_ scheme: ColorScheme) -> some View {
        if scheme == .dark {
            ZStack {
                Color.black.opacity(0.24)
                Color(red: 6 / 255, green: 10 / 255, blue: 16 / 255).opacity(0.12)
                LinearGradient(colors: [Color(red: 3 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.08),
                                        Color(red: 3 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.42)],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            LinearGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0.52)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

extension EnvironmentValues {
    /// The window's size, which the backdrop photo fills (``HouseBackdrop``); zero until the root measures it.
    @Entry var backdropCanvas: CGSize = .zero
}
