import HassCore
import HassDesign
import SwiftUI

// MARK: - Rows of the recipe sheet's inset lists

/// Leading glyph width in the recipe sheet's rows, so titles line up and hairlines start at the text.
enum RecipeRowMetrics {
    /// The glyph column.
    static let glyph: CGFloat = 28
    /// Space between the glyph and the text.
    static let gap = HassTokens.Spacing.l
    /// A row's minimum height (direction G, Controls: Lists: 52 pt rows).
    static let minHeight: CGFloat = 52
    /// Where a hairline starts in a row with a glyph: the row's padding, the glyph and the gap.
    static let textInset = HassTokens.Spacing.l + glyph + gap
}

/// A hairline between two rows of an inset list, inset to the text (direction G, Controls: Lists).
struct RecipeRowDivider: View {
    /// Where the hairline starts.
    var inset: CGFloat = RecipeRowMetrics.textInset

    var body: some View {
        Divider()
            .overlay(HassTokens.Surface.separator)
            .padding(.leading, inset)
    }
}

/// One fact on the General tab: glyph, label and the value trailing in secondary ink (mockup n6 recipe detail).
/// At accessibility sizes the value moves under the label and the glyph is dropped, so both wrap whole words.
struct RecipeFactRow: View {
    let fact: RecipeFormatting.Fact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        let text = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s))
        HStack(spacing: RecipeRowMetrics.gap) {
            if !large {
                Image(systemName: fact.symbol)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .frame(width: RecipeRowMetrics.glyph)
                    .accessibilityHidden(true)
            }
            text {
                Text(fact.label)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !large { Spacer(minLength: HassTokens.Spacing.s) }
                Text(fact.value)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .multilineTextAlignment(large ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: RecipeRowMetrics.minHeight, alignment: .leading)
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

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: RecipeRowMetrics.gap) {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: RecipeRowMetrics.glyph)
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
        .buttonStyle(.plain)
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
