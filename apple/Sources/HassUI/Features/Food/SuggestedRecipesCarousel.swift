import HassCore
import HassDesign
import SwiftUI

/// The hub's Suggested Recipes: five swipeable pages of compact recipe cards (web `SuggestedRecipeCarousel` +
/// `CardCarousel`). Columns follow the width like the web (min 2, cards up to 220 pt, max 10); three rows
/// on narrow windows and two on wide ones. Empty slots keep their place while loading.
struct SuggestedRecipesCarousel: View {
    let model: SuggestedRecipesModel
    var onOpen: (RecipeCard) -> Void
    @State private var width: CGFloat = 0
    @State private var page: Int? = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Web `RECOMMENDATION_PAGE_COUNT`.
    static let pageCount = 5
    static let spacing: CGFloat = 10

    /// Columns and rows for a width (web `recommendationLayout`). At accessibility text sizes cards are
    /// twice as wide (one column on iPhone) and pages hold two rows, so titles wrap instead of truncating.
    static func layout(width: CGFloat, accessibilitySize: Bool = false) -> (columns: Int, rows: Int) {
        if accessibilitySize {
            return (min(10, max(1, Int(((width + spacing) / (440 + spacing)).rounded(.down)))), 2)
        }
        let columns = max(2, Int(((width + spacing) / (220 + spacing)).rounded(.up)))
        return (min(10, columns), width >= 900 ? 2 : 3)
    }

    private var layout: (columns: Int, rows: Int) { Self.layout(width: width, accessibilitySize: dynamicTypeSize.isAccessibilitySize) }
    private var pageSize: Int { layout.columns * layout.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            switch model.phase {
            case .failed:
                ContentUnavailableView(
                    "Suggestions Unavailable", systemImage: "fork.knife",
                    description: Text("Suggested recipes are temporarily unavailable.")
                )
                .accessibilityIdentifier("food.suggestions.error")
            default:
                pages
                if pageCount > 1 { pageControl }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested recipes")
        .accessibilityIdentifier("food.suggestions")
    }

    /// Pages that hold cards (always five while loading, so the frame does not jump).
    private var pageCount: Int {
        model.phase == .ready ? max(1, min(Self.pageCount, Int((Double(model.items.count) / Double(max(pageSize, 1))).rounded(.up)))) : Self.pageCount
    }

    private var pages: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    pageGrid(index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        // The next page peeks in at standard sizes; at accessibility sizes the sliver is unreadable (and
        // unmeasurable by the contrast audit), so pages clip and the dots carry the paging.
        .scrollClipDisabled(!dynamicTypeSize.isAccessibilitySize)
    }

    private func pageGrid(_ index: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: layout.columns)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
            ForEach(0..<pageSize, id: \.self) { slot in
                let position = index * pageSize + slot
                if model.phase == .ready, position < model.items.count {
                    let recipe = model.items[position]
                    ImageCard(
                        title: recipe.title, imageURL: recipe.cardImageURL, fallbackImageURL: recipe.imageURL,
                        placeholderSymbol: "fork.knife", accessibilityHint: "Opens recipe details", reservedTitleLines: 2
                    ) { onOpen(recipe) }
                    .accessibilityIdentifier("food.suggestion.\(recipe.id)")
                } else if model.phase != .ready {
                    RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .aspectRatio(0.95, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.trailing, Self.spacing)
    }

    /// The page after a VoiceOver swipe up (next) or down (previous), clamped to the pages.
    static func adjusted(_ page: Int?, _ direction: AccessibilityAdjustmentDirection, pageCount: Int) -> Int {
        let current = page ?? 0
        switch direction {
        case .increment: return min(pageCount - 1, current + 1)
        case .decrement: return max(0, current - 1)
        @unknown default: return current
        }
    }

    /// Page dots with VoiceOver adjustable paging (web carousel dots).
    private var pageControl: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == (page ?? 0) ? HassTokens.Ink.primary : HassTokens.Ink.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Suggestion page")
        .accessibilityValue("\((page ?? 0) + 1) of \(pageCount)")
        .accessibilityAdjustableAction { direction in
            withAnimation { page = Self.adjusted(page, direction, pageCount: pageCount) }
        }
        .accessibilityIdentifier("food.suggestions.pages")
    }
}
