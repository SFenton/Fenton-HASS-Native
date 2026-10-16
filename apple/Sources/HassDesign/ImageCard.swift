import SwiftUI

/// A tappable card with a remote image, a title and an optional subtitle (pattern: `.agents/patterns/image-card.md`).
///
/// Used for recipes on the Food hub carousel and the Recipes grid (web `ImageCard`). Pure UI: callers pass
/// values and an action.
///
/// Direction G (mockups n6): the photo fills a 22 pt card and the caption sits on it in white over a bottom scrim, as in
/// Photos and Music. At accessibility text sizes the card is a row with a small thumbnail on a module instead.
///
/// The caption is the card's one accessibility element, framed to the text alone: the whole card is still the tap
/// target, but VoiceOver and the rendered-contrast audit see the caption over its scrim rather than a card-sized
/// element that is mostly photo (audit item 12).
public struct ImageCard: View {
    // MARK: - Inputs

    public var title: String
    public var subtitle: String?
    public var imageURL: URL?
    /// Tried when ``imageURL`` fails (web `fallbackImageUrl`).
    public var fallbackImageURL: URL?
    /// SF Symbol drawn when no image loads.
    public var placeholderSymbol: String
    /// What VoiceOver says the card does, e.g. "Opens recipe details".
    public var accessibilityHint: String
    public var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The card's corner radius (direction G, Controls: 22 pt, as tiles). Callers drawing a selection outline use it.
    public static let cornerRadius = HassTokens.Radius.tile
    /// Width over height of the photo card (mockups n6: 1 : 0.78). Loading placeholders use it to keep the layout.
    public static let aspectRatio: CGFloat = 1 / 0.78

    /// Creates a card.
    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        fallbackImageURL: URL? = nil,
        placeholderSymbol: String = "photo",
        accessibilityHint: String = "",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.fallbackImageURL = fallbackImageURL
        self.placeholderSymbol = placeholderSymbol
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var image: some View {
        RemoteImage(url: imageURL, fallbackURL: fallbackImageURL, placeholderSymbol: placeholderSymbol)
    }

    /// The caption: white on the photo's scrim, or primary and secondary ink on a module at accessibility sizes.
    private func labels(onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(onPhoto ? Color.white : HassTokens.Ink.primary)
                .lineLimit(Self.titleLines(accessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(onPhoto ? Color.white.opacity(0.86) : HassTokens.Surface.secondaryOnModule)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .shadow(color: onPhoto ? .black.opacity(0.6) : .clear, radius: 3, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The card's one element (see the type's documentation). The button underneath takes the taps.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    /// Title lines: up to three; never truncated at accessibility text sizes, where a cut title fails the Dynamic
    /// Type audit.
    static func titleLines(accessibilitySize: Bool) -> ClosedRange<Int> {
        accessibilitySize ? 1...100 : 1...3
    }

    /// The scrim under the caption (mockups n6: clear over the top third, near black at the foot), so white text keeps
    /// 4.5:1 on a white plate.
    static var scrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0.3),
                .init(color: .black.opacity(0.55), location: 0.62),
                .init(color: .black.opacity(0.8), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Body

    public var body: some View {
        let accessibilitySize = dynamicTypeSize.isAccessibilitySize
        Button(action: action) {
            if accessibilitySize {
                // Large text: a row with a small thumbnail, so the title (not the picture) fills the card
                // (HIG Typography: prioritize text at accessibility sizes). A hidden copy of the caption sizes the row;
                // the visible one is laid over it below.
                HStack(alignment: .top, spacing: HassTokens.Spacing.m) {
                    image
                        .frame(width: Self.thumbnail, height: Self.thumbnail)
                        .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
                    labels(onPhoto: false).hidden()
                }
                .padding(HassTokens.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .module(cornerRadius: Self.cornerRadius)
            } else {
                Color.clear
                    .aspectRatio(Self.aspectRatio, contentMode: .fit)
                    .overlay { image }
                    .overlay { Self.scrim }
                    .module(cornerRadius: Self.cornerRadius)
                    .clipShape(shape)
            }
        }
        .buttonStyle(.plain)
        .contentShape(shape)
        // VoiceOver reaches the card through its caption.
        .accessibilityHidden(true)
        .overlay(alignment: accessibilitySize ? .topLeading : .bottomLeading) {
            if accessibilitySize {
                labels(onPhoto: false)
                    .padding(.leading, HassTokens.Spacing.m * 2 + Self.thumbnail)
                    .padding([.top, .trailing], HassTokens.Spacing.m)
            } else {
                labels(onPhoto: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }

    /// The thumbnail's side at accessibility sizes.
    private static let thumbnail: CGFloat = 72
}

/// A cached remote image (``CachedImage``) that tries a fallback URL, then a symbol, and never shows a broken
/// image. Holds an enclosing ``ContentGate`` until it draws.
public struct RemoteImage: View {
    public var url: URL?
    public var fallbackURL: URL?
    public var placeholderSymbol: String
    @State private var useFallback = false

    /// Creates an image.
    public init(url: URL?, fallbackURL: URL? = nil, placeholderSymbol: String = "photo") {
        self.url = url
        self.fallbackURL = fallbackURL
        self.placeholderSymbol = placeholderSymbol
    }

    private var current: URL? {
        if useFallback || url == nil { return fallbackURL == url ? nil : fallbackURL }
        return url
    }

    public var body: some View {
        // No fill of its own: the card's surface shows through behind the placeholder, so the card is one
        // surface. A tinted fill (even 5%) was a second surface that rendered-contrast sampling read as text,
        // measuring image cards at ~1.1:1 on iPad. Loaded images cover the area.
        Color.clear
            .overlay {
                if let current {
                    CachedImage(url: current, onFailure: { if !useFallback, fallbackURL != nil { useFallback = true } }) {
                        placeholder
                    }
                    .id(current)
                } else {
                    placeholder
                }
            }
            .clipped()
            // Decorative and never a touch target. `.clipped()` limits drawing, not hit testing: a fill-scaled
            // photo overflowing its frame covered the recipe tabs above it and swallowed their taps (live recipe
            // on iPad, 2026-10-12). Cards keep their taps through the button's content shape.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        // Secondary ink, not `.secondary`: the system gray on the gray fill is about 3:1, and at large text
        // sizes the symbol fills the card and fails the card's contrast audit.
        Image(systemName: placeholderSymbol)
            .font(.largeTitle)
            .foregroundStyle(HassTokens.Ink.secondary)
    }
}
