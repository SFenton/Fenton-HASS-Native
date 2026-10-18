import FentonActivityModel
import HassDesign
import SwiftUI

/// The house and heart in a card's corner: 40 pt, no tile, tinted with the foreground colour of the app icon the person
/// picked in Settings → Appearance → App Icon (`.agents/platforms/apple/live-activities-per-job.md` §8).
///
/// The app writes the choice to the app group (`ActivityAppIconStore`); the widget reads it and falls back to Navy + Sky.
/// The colours below mirror `AppIconChoice.glyph` (HassCore, which the widget does not link); a HassUI test compares them
/// for every choice, so they cannot drift.
public enum CornerMarkPalette {
    /// The foreground colour of each `AppIconChoice` raw value, as `0xRRGGBB`.
    public static let glyphs: [String: UInt32] = [
        "navySky": 0x7CC4FF, "tealMint": 0x6EE7C8, "plumLilac": 0xD3A8FF, "forestGreen": 0x9BE29B,
        "burgundyRose": 0xFF9EB0, "indigoPeriwinkle": 0xA8B4FF, "espressoAmber": 0xFFB35C, "midnightGold": 0xFFD36B,
    ]

    /// The colour for a stored choice; an unknown or missing one reads Navy + Sky.
    public static func glyph(for choice: String?) -> UInt32 {
        choice.flatMap { glyphs[$0] } ?? glyphs[ActivityAppIconStore.fallback] ?? 0x7CC4FF
    }
}

private struct CornerMarkChoiceKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    /// The `AppIconChoice` raw value the corner mark follows; nil reads the app group's stored choice.
    var cornerMarkChoice: String? {
        get { self[CornerMarkChoiceKey.self] }
        set { self[CornerMarkChoiceKey.self] = newValue }
    }
}

/// The corner mark. It is decoration: the card's own label says what it is.
struct CornerMark: View {
    @Environment(\.cornerMarkChoice) private var choice

    var body: some View {
        HouseHeartShape()
            .fill(Color(rgb: CornerMarkPalette.glyph(for: choice ?? ActivityAppIconStore.shared.choice)))
            .frame(width: ActivityStyle.markSize, height: ActivityStyle.markSize)
            .accessibilityHidden(true)
    }
}
