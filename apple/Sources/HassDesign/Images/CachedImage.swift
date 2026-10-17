import ImageIO
import SwiftUI

/// A remote image drawn from ``ImagePipeline`` (pattern: `.agents/patterns/image-cache.md`).
///
/// - An image already in memory draws on the first frame, so cells scrolling back into view never flash.
/// - When the URL changes (a rotated camera token, new artwork), the current image stays up until the next one
///   decodes, then cross-fades.
/// - Inside a ``ContentGate`` it holds the gate until it has drawn or failed.
///
/// Decorative: callers label the element that contains it.
public struct CachedImage<Placeholder: View>: View {
    private var url: URL?
    private var contentMode: ContentMode
    private var pipeline: ImagePipeline
    private var onFailure: (() -> Void)?
    private var placeholder: Placeholder

    @State private var image: CGImage?
    @State private var shownKey: String?
    @State private var failed = false
    @State private var pixelSize = 0
    @Environment(\.displayScale) private var displayScale

    /// Creates an image.
    /// - Parameters:
    ///   - url: The image; `nil` shows the placeholder.
    ///   - contentMode: How the image fills the frame.
    ///   - pipeline: The cache (tests pass their own).
    ///   - onFailure: Called once when nothing loads (callers switch to a fallback URL).
    ///   - placeholder: Drawn when there is no URL or nothing loads. While loading the frame stays empty, so a
    ///     fast load fades straight in without a placeholder flash.
    public init(
        url: URL?,
        contentMode: ContentMode = .fill,
        pipeline: ImagePipeline = .shared,
        onFailure: (() -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.pipeline = pipeline
        self.onFailure = onFailure
        self.placeholder = placeholder()
        let cached = url.flatMap(pipeline.memoryImage(for:))
        _image = State(initialValue: cached)
        _shownKey = State(initialValue: cached == nil ? nil : url.map(ImagePipeline.key(for:)))
    }

    private struct LoadKey: Equatable {
        var url: URL?
        var pixels: Int
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if url == nil || failed {
                placeholder
            }
        }
        // The fade belongs to this subtree. It used to be `withAnimation` around the state write, which put everything
        // that changed in that update, the card around the photo included, in an animating transaction (a card grid
        // creating cards as it scrolls spent a sixth of its busiest turns in animatable frames and the opacity transition).
        .animation(.easeOut(duration: 0.2), value: shownKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Int.self) { proxy in
            ImagePipeline.bucket(Int(max(proxy.size.width, proxy.size.height) * displayScale))
        } action: { pixelSize = $0 }
        .task(id: LoadKey(url: url, pixels: pixelSize)) { await load() }
        .contentReadiness("image:\(url?.absoluteString ?? "none")", isReady: url == nil || image != nil || failed)
    }

    private func load() async {
        guard pixelSize > 0 else { return }
        guard let url else {
            image = nil
            return
        }
        var yielded = false
        for await next in pipeline.images(for: url, maxPixel: pixelSize) {
            yielded = true
            let key = ImagePipeline.key(for: url)
            // A first image fades in; a replacement for a different URL cross-fades; a same-size refresh of the
            // image already shown swaps without animation.
            // (`shownKey` changes with a first image or a different URL, which is what the body's animation watches.)
            image = next
            shownKey = key
            failed = false
        }
        if !yielded, !Task.isCancelled {
            failed = true
            onFailure?()
        }
    }
}

public extension CachedImage where Placeholder == Color {
    /// An image with a clear placeholder.
    init(url: URL?, contentMode: ContentMode = .fill, pipeline: ImagePipeline = .shared) {
        self.init(url: url, contentMode: contentMode, pipeline: pipeline) { Color.clear }
    }
}
