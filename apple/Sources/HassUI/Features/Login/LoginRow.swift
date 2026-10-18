import HassCore
import HassDesign
import SwiftUI

/// One row: its label, then its field. At accessibility sizes the label sits above the field instead of beside it, so
/// neither is squeezed.
struct LoginRow<Field: View>: View {
    var label: String
    @ViewBuilder var field: Field

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 96

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.m))
        layout {
            Text(label)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: typeSize.isAccessibilitySize ? nil : labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            field
                .font(.body)
                .foregroundStyle(.white)
                .tint(Color(rgb: HassTokens.Palette.tintText))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, typeSize.isAccessibilitySize ? HassTokens.Spacing.m : 0)
        .frame(minHeight: minHeight)
    }
}
