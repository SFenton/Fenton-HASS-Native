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
/// The photo itself loads through ``ImagePipeline`` (disk cache, conditional revalidation, updates when the server's
/// file changes; `.agents/patterns/image-cache.md`). No reload on reopen: the blurred render is also kept on disk and
/// read synchronously at launch, so the first frame already shows it; ``refresh()`` re-renders whatever the
/// pipeline yields (the cached photo, then a changed one).
@MainActor
@Observable
final class HouseBackdropStore {
    /// The blurred render, once known.
    private(set) var image: CGImage?

    @ObservationIgnored private let source: URL
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let photos: @Sendable (URL) -> AsyncStream<CGImage>
    @ObservationIgnored private var refreshed = false

    /// Creates the store and loads the cached render.
    /// - Parameters:
    ///   - server: The signed-in server, which serves the photo.
    ///   - directory: Where the blurred render is cached.
    ///   - photos: The photo's images, cached first then fresh (tests pass a stub).
    init(server: HassServer, directory: URL = HouseBackdropStore.defaultDirectory,
         photos: @escaping @Sendable (URL) -> AsyncStream<CGImage> = HouseBackdropStore.pipelinePhotos) {
        source = Self.imageURL(for: server)
        self.directory = directory
        self.photos = photos
        image = Self.loadImage(at: directory.appending(path: Self.renderName))
    }

    /// Renders each photo the pipeline yields, once per store. Failures keep the cached render.
    func refresh() async {
        guard !refreshed else { return }
        refreshed = true
        let renderURL = directory.appending(path: Self.renderName)
        let directory = directory
        for await photo in photos(source) {
            let rendered: CGImage? = await Task.detached(priority: .utility) {
                guard let render = Self.render(photo) else { return nil }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                Self.write(render, to: renderURL)
                return render
            }.value
            if let rendered { image = rendered }
        }
    }

    // MARK: Pure helpers

    /// The blurred render's file name in the cache. Renamed when the render recipe changes, so an old render
    /// is never shown under the new scrim.
    nonisolated static let renderName = "house-blurred-g.png"
    /// Width the photo is reduced to before blurring; the blur hides the lost detail.
    nonisolated static let renderWidth: CGFloat = 480
    /// Blur radius at ``renderWidth`` (direction G: `blur(20px)` over a phone-width viewport, about 400 px).
    nonisolated static let blurRadius: Double = 20
    /// Saturation boost (direction G: `saturate(1.1)`).
    nonisolated static let saturation: Double = 1.1

    /// `<server>/local/images/house.webp`, Home Assistant's public `www` folder (no sign-in needed).
    nonisolated static func imageURL(for server: HassServer) -> URL {
        server.baseURL.appending(path: "local/images/house.webp")
    }

    /// The photo from the shared ``ImagePipeline``, decoded at the render width.
    nonisolated static func pipelinePhotos(_ url: URL) -> AsyncStream<CGImage> {
        ImagePipeline.shared.images(for: url, maxPixel: Int(renderWidth))
    }

    /// The cache folder: Caches/HouseBackdrop.
    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "HouseBackdrop", directoryHint: .isDirectory)
    }

    /// Downsizes, saturates (``saturation``) and blurs the photo once. Darkening is left to the view's scrim.
    /// - Parameter photo: The decoded photo.
    /// - Returns: The render, or nil when Core Image can't draw it.
    nonisolated static func render(_ photo: CGImage) -> CGImage? {
        var image = CIImage(cgImage: photo)
        let scale = min(1, renderWidth / max(1, image.extent.width))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        image = image.clampedToExtent()
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
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

/// The page background: the house photo, blurred and under direction G's dark scrim
/// (`.agents/design/direction-g.md`, Layers), drawn once per page by `pageChrome()`. Modals have none. Pages are
/// always dark (the shell sets `preferredColorScheme(.dark)`), the way Apple Home's wallpaper works.
///
/// Every page shows the same crop: the photo fills the window (``EnvironmentValues/backdropCanvas``) and each
/// page, split pane included, shows the part of it under its own frame, so a split reads as one picture.
/// Reduce Transparency draws the plain background instead.
struct HouseBackdrop: View {
    @Environment(HouseBackdropStore.self) private var store: HouseBackdropStore?
    @Environment(\.backdropCanvas) private var canvas
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HouseBackdropStyle.base
                if let image = store?.image, !reduceTransparency {
                    let size = canvas == .zero ? proxy.size : canvas
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(HouseBackdropStyle.scale)
                        // Shift by this page's window position without re-running the body each transition frame.
                        .visualEffect { content, proxy in
                            let origin = proxy.frame(in: .global).origin
                            return content.offset(x: -origin.x, y: -origin.y)
                        }
                        .transition(.opacity)
                    HouseBackdropStyle.scrim
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: store?.image != nil)
    }
}

/// The backdrop's layers (direction G, Layers: the photo scaled 1.06 under a black scrim).
enum HouseBackdropStyle {
    /// Under the photo, and the whole backdrop with Reduce Transparency: the web shell's `#111723`.
    static let base = Color(red: 17 / 255, green: 23 / 255, blue: 35 / 255)

    /// How far the photo is scaled past the window, so the blur's soft edges stay off screen.
    static let scale: CGFloat = 1.06

    /// The scrim's black opacity from top to bottom: lighter where the large title sits over the house, denser
    /// behind the tab bar.
    static let scrimStops: [Gradient.Stop] = [
        .init(color: .black.opacity(0.36), location: 0),
        .init(color: .black.opacity(0.18), location: 0.28),
        .init(color: .black.opacity(0.36), location: 0.50),
        .init(color: .black.opacity(0.50), location: 0.75),
        .init(color: .black.opacity(0.64), location: 1),
    ]

    /// Over the photo.
    static var scrim: some View {
        LinearGradient(stops: scrimStops, startPoint: .top, endPoint: .bottom)
    }
}

extension EnvironmentValues {
    /// The window's size, which the backdrop photo fills (``HouseBackdrop``); zero until the root measures it.
    @Entry var backdropCanvas: CGSize = .zero
}
