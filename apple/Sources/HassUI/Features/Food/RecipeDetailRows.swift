import HassCore
import HassDesign
import SwiftUI

// MARK: - Rows of the recipe sheet's inset lists

/// Measurements of the recipe sheet's own rows (ingredients, steps, the source link), matching ``ModuleRow`` so their
/// text starts where ``ModuleList`` insets its hairlines.
enum RecipeRowMetrics {
    /// The glyph column (``ModuleRow``'s).
    static let glyph = ModuleRowMetrics.glyphWidth
    /// Space between the glyph and the text (``ModuleRow``'s).
    static let gap = ModuleRowMetrics.gap
    /// A row's minimum height (direction G, Controls: Lists: 52 pt rows).
    static let minHeight: CGFloat = 52
}

/// One fact on the General tab: glyph, label and the value trailing in secondary ink (mockup n6 recipe detail), a
/// ``ModuleRow``. At accessibility sizes the value moves under the label, so both wrap whole words.
struct RecipeFactRow: View {
    let fact: RecipeFormatting.Fact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ModuleRow(fact.label, symbol: fact.symbol, glyph: HassTokens.Ink.secondary) {
            Text(fact.value)
                .foregroundStyle(HassTokens.Ink.secondary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.label)
        .accessibilityValue(fact.spokenValue ?? fact.value)
    }
}

/// A list row that opens a web page through `openURL`, in the action tint ("Open Source Recipe"), the way direction G
/// puts secondary actions in a sheet's list rather than in a second filled button.
struct RecipeLinkRow: View {
    var title: String
    var url: URL
    @Environment(\.openURL) private var openURL
    /// The glyph's column, scaled like ``ModuleList``'s hairline inset.
    @ScaledMetric(relativeTo: .body) private var glyphWidth = RecipeRowMetrics.glyph

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: RecipeRowMetrics.gap) {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: glyphWidth)
                    .accessibilityHidden(true)
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(HassTokens.Ink.action)
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: RecipeRowMetrics.minHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModuleRowButtonStyle())
        .accessibilityAddTraits(.isLink)
    }
}

/// One numbered instruction step.
struct RecipeStepRow: View {
    let step: RecipeDetail.Step

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Text("\(step.number).")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(HassTokens.Ink.secondary)
            Text(step.text)
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: RecipeRowMetrics.minHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.number). \(step.text)")
    }
}
