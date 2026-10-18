import FentonActivityModel
import HassDesign
import SwiftUI

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

/// The house and heart in a card's corner: 40 pt, no tile, tinted with the foreground colour of the app icon the person
/// picked (``CornerMarkPalette``). It is decoration: the card's own label says what it is.
struct CornerMark: View {
    @Environment(\.cornerMarkChoice) private var choice

    var body: some View {
        HouseHeartShape()
            .fill(Color(rgb: CornerMarkPalette.glyph(for: choice ?? ActivityAppIconStore.shared.choice)))
            .frame(width: ActivityStyle.markSize, height: ActivityStyle.markSize)
            .accessibilityHidden(true)
    }
}
