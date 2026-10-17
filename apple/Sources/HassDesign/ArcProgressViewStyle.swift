import SwiftUI

/// Draws an indeterminate `ProgressView` as an ``ArcSpinner`` with its title underneath, so a titled spinner
/// ("Loading recipes") keeps its words in the web's arc style. A determinate `ProgressView(value:)` keeps the
/// linear bar.
///
/// ```swift
/// ProgressView("Loading recipes").progressViewStyle(.arc)
/// ```
public struct ArcProgressViewStyle: ProgressViewStyle {
    private let size: ArcSpinner.Size
    @Environment(\.tileSurface) private var surface

    /// Creates the style.
    /// - Parameter size: How big to draw the arc.
    public init(size: ArcSpinner.Size = .page) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        if configuration.fractionCompleted != nil {
            ProgressView(configuration).progressViewStyle(.linear)
        } else {
            VStack(spacing: HassTokens.Spacing.s) {
                // The title says what is loading, so the arc itself stays silent.
                ArcSpinner(size).accessibilityHidden(true)
                configuration.label
                    .font(.subheadline)
                    // `.secondary` measured 3.1:1 over the wallpaper (Direction G gallery, iPad): a page title takes the
                    // wallpaper's secondary ink, a sheet's the sheet's.
                    .foregroundStyle(surface == .sheet ? HassTokens.Surface.secondaryInSheet : HassTokens.Surface.secondaryOnWallpaper)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

public extension ProgressViewStyle where Self == ArcProgressViewStyle {
    /// The web's arc with the title underneath (``ArcProgressViewStyle``).
    static var arc: ArcProgressViewStyle { ArcProgressViewStyle() }

    /// The web's arc at `size` with the title underneath.
    static func arc(_ size: ArcSpinner.Size) -> ArcProgressViewStyle { ArcProgressViewStyle(size: size) }
}

#Preview("Titled arc spinner") {
    ProgressView("Loading recipes")
        .progressViewStyle(.arc)
        .padding()
        .background(.black)
        .foregroundStyle(.white)
}
