import FentonActivityModel
import HassDesign
import SwiftUI

/// Direction G for the Live Activity (`.agents/design/direction-g.md`, Colour families): a job's glyph and bar take
/// its device family's colour, and its row is a tinted glass of that family on the activity's dark ground.
///
/// The Lock Screen background is a dark tint and the Dynamic Island is always black, so these use the dark values
/// of the family (never `ColorFamily.glyph`, which adapts to the appearance of a page or sheet).
public struct ActivityStyle: Sendable, Equatable {
    /// The family.
    public let family: ColorFamily

    /// The style for a job's `tint` name (a `ColorFamily` raw value; unknown names read neutral).
    public init(tint: String) {
        family = ColorFamily(rawValue: tint) ?? .neutral
    }

    /// The glyph, bar and countdown accent on the dark ground (at least 3:1 on black, WCAG 1.4.11).
    public var accent: Color { Color(rgb: family.spec.glyph) }

    /// The row's tinted glass: the family fill at a low opacity over the dark ground, grey for neutral.
    public func rowFill(dimmed: Bool = false) -> Color {
        Color(rgb: family.spec.fill ?? 0x48484A).opacity(dimmed ? 0.22 : 0.42)
    }

    /// White at the opacity text needs on ``rowFill``: 4.5:1 or better.
    public static let primaryText = Color.white
    /// Supporting text on the row.
    public static let secondaryText = Color.white.opacity(0.78)
    /// How dark the activity's background tint is. The system material lets a bright wallpaper through, so this is the
    /// darkest that still looks like glass: text on a row reads even over white (`ActivityStyleTests`).
    public static let groundOpacity = 0.75
    /// The activity's background tint on the Lock Screen (`activityBackgroundTint`).
    public static let ground = Color.black.opacity(groundOpacity)
    /// Destructive text on the dark ground (``HassTokens/Palette/red``).
    public static let destructive = Color(rgb: HassTokens.Palette.red)

    /// Smallest comfortable hit area for a button (HIG: 44 pt).
    public static let minimumHit: CGFloat = 44
}
