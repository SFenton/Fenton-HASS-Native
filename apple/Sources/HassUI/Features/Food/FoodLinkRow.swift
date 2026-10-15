import HassDesign
import SwiftUI

/// A row on the Food hub that opens a page: leading glyph, title, optional count line and a chevron, as a one-row
/// ``ModuleList`` on the wallpaper (direction G mockups n6 Food & Recipes: "All Recipes" and "All Food").
///
/// One button per row: VoiceOver reads the title, then the subtitle as its value. The row grows with Dynamic Type and
/// its text wraps instead of truncating; the whole row is the 44 pt (or taller) target.
struct FoodLinkRow: View {
    var title: String
    var subtitle: String?
    var symbol: String
    /// The button's accessibility identifier (`food.allRecipes`), set on the button itself rather than on the list.
    var identifier: String
    var action: () -> Void

    var body: some View {
        ModuleList {
            Button(action: action) {
                ModuleRow(title, subtitle: subtitle, symbol: symbol, showsChevron: true)
            }
            .buttonStyle(ModuleRowButtonStyle())
            .accessibilityLabel(title)
            .accessibilityValue(subtitle ?? "")
            .accessibilityIdentifier(identifier)
        }
    }
}
