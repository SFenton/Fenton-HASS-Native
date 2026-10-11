import SwiftUI

/// A tappable card with a remote image, a title and an optional subtitle (pattern: `.agents/patterns/image-card.md`).
///
/// Used for recipes on the Food hub carousel and the Recipes grid (web `ImageCard`). Pure UI: callers pass
/// values and an action.
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
    /// When set, the title always takes this many lines so cards in a row line up (carousels).
    public var reservedTitleLines: Int?
    public var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a card.
    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        fallbackImageURL: URL? = nil,
        placeholderSymbol: String = "photo",
        accessibilityHint: String = "",
        reservedTitleLines: Int? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.fallbackImageURL = fallbackImageURL
        self.placeholderSymbol = placeholderSymbol
        self.accessibilityHint = accessibilityHint
        self.reservedTitleLines = reservedTitleLines
        self.action = action
    }

    private var image: some View {
        RemoteImage(url: imageURL, fallbackURL: fallbackImageURL, placeholderSymbol: placeholderSymbol)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .lineLimit(Self.titleLines(reserved: reservedTitleLines, accessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Title lines: the reserved count (so a row lines up), else up to three; never truncated at
    /// accessibility text sizes, where a cut title fails the Dynamic Type audit.
    static func titleLines(reserved: Int?, accessibilitySize: Bool) -> ClosedRange<Int> {
        if accessibilitySize { return 1...100 }
        if let reserved { return reserved...reserved }
        return 1...3
    }

    // MARK: - Body

    public var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Large text: a row with a small thumbnail, so the title (not the picture) fills the card
                    // (HIG Typography: prioritize text at accessibility sizes).
                    HStack(alignment: .top, spacing: HassTokens.Spacing.m) {
                        image
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
                        labels
                    }
                    .padding(HassTokens.Spacing.m)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        image
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipped()
                        labels.padding(HassTokens.Spacing.m)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

/// An `AsyncImage` that tries a fallback URL, then a symbol, and never shows a broken image.
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
        Color.secondary.opacity(0.12)
            .overlay {
                if let current {
                    AsyncImage(url: current, transaction: Transaction(animation: .easeOut(duration: 0.2))) { self.phase($0) }
                        .id(current)
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    /// What one `AsyncImage` phase draws: the image, the placeholder (switching to the fallback URL once)
    /// or a spinner.
    @ViewBuilder
    func phase(_ phase: AsyncImagePhase) -> some View {
        switch phase {
        case let .success(image):
            image.resizable().scaledToFill()
        case .failure:
            placeholder.onAppear { if !useFallback, fallbackURL != nil { useFallback = true } }
        default:
            ProgressView()
        }
    }

    private var placeholder: some View {
        // Secondary ink, not `.secondary`: the system gray on the gray fill is about 3:1, and at large text
        // sizes the symbol fills the card and fails the card's contrast audit.
        Image(systemName: placeholderSymbol)
            .font(.largeTitle)
            .foregroundStyle(HassTokens.Ink.secondary)
    }
}
