import HassDesign
import SwiftUI

/// A row on the Food hub that opens a page: leading glyph, title, optional count line and a chevron, on a direction G
/// module (mockups n6 Food & Recipes: "All Recipes" and "All Food").
///
/// One button per row: VoiceOver reads the title, then the subtitle as its value. The row grows with Dynamic Type and
/// its text wraps instead of truncating; the whole row is the 44 pt (or taller) target.
struct FoodLinkRow: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: HassTokens.Spacing.l) {
                // Decorative: the title names the row. Hidden at accessibility sizes, where it would take the text's room.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(HassTokens.Surface.secondaryOnModule)
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(HassTokens.Ink.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(HassTokens.Surface.secondaryOnModule)
                            .monospacedDigit()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HassTokens.Surface.secondaryOnModule)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
            // 52 pt rows, 60 pt with a subtitle (direction G, Controls: Lists).
            .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 52 : 60, alignment: .leading)
            // G: ModuleList (a one-row inset list until `ModuleList`/`ModuleRow` land)
            .module()
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.module))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }
}
