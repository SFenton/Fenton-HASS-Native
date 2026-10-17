import HassCore
import HassDesign
import SwiftUI

/// A small copy of an app icon: the same art the asset catalog's PNGs are rendered from (``AppIconArtwork``), clipped to
/// the system's icon corner radius (about 22.4% of the side). Drawing it from the one source means a preview can never
/// differ from the icon it stands for. Decorative: the row or button around it carries the name.
struct AppIconPreview: View {
    let choice: AppIconChoice
    let side: CGFloat

    /// The Home Screen icon's corner radius as a fraction of its side.
    static let cornerFraction: CGFloat = 0.2237

    var body: some View {
        AppIconArtwork(tint: choice.tint, tintOpacity: AppIconChoice.tintOpacity, ring: choice.ring, glyph: choice.glyph)
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: side * Self.cornerFraction, style: .continuous))
            .overlay {
                // A hairline so the icon's edge reads on a white sheet as on a dark one.
                RoundedRectangle(cornerRadius: side * Self.cornerFraction, style: .continuous)
                    .strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
