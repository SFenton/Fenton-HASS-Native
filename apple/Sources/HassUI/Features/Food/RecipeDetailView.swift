import HassCore
import HassDesign
import SwiftUI

// MARK: - Presentations

/// The recipe detail as a sheet (web `RecipeDetailModal`): large detent, its own navigation bar with Done.
struct RecipeDetailSheet: View {
    let model: RecipeDetailModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RecipeDetailContent(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("recipe.done")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The recipe detail in the trailing half of a split (iPad and unfolded iPhone Duo landscape).
struct RecipeDetailPane: View {
    let model: RecipeDetailModel
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            RecipeDetailContent(model: model)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                            .accessibilityIdentifier("recipe.close")
                    }
                }
        }
        .id(model.recipe.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe.pane")
    }
}

// MARK: - Content

/// Title, tab picker and the selected tab (web `RECIPE_DETAIL_TABS`: General, Ingredients, Instructions).
struct RecipeDetailContent: View {
    @Bindable var model: RecipeDetailModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Loading recipe details")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("recipe.loading")
            case let .failed(message, unsupported):
                ContentUnavailableView(
                    unsupported ? "Recipe Details Unsupported" : "Unable to Load Recipe",
                    systemImage: "exclamationmark.triangle", description: Text(message)
                )
                .accessibilityIdentifier("recipe.error")
            case let .loaded(detail):
                loaded(detail)
            }
        }
        .navigationTitle(model.detail?.title ?? model.recipe.title)
        .inlineNavigationTitle()
        .onAppear { model.load() }
    }

    private func loaded(_ detail: RecipeDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                Picker("Section", selection: $model.tab) {
                    ForEach(RecipeDetailModel.Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("recipe.tabs")
                switch model.tab {
                case .general: RecipeGeneralTab(detail: detail, fallbackImageURL: model.recipe.imageURL)
                case .ingredients: RecipeIngredientsTab(detail: detail, model: model)
                case .instructions: RecipeInstructionsTab(detail: detail)
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .accessibilityIdentifier("recipe.scroll")
    }
}

// MARK: - General

/// Hero image, facts, equipment and the source link (web `GeneralTab`).
struct RecipeGeneralTab: View {
    let detail: RecipeDetail
    var fallbackImageURL: URL?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
            RemoteImage(url: detail.primaryImageURL ?? detail.thumbnailURL, fallbackURL: fallbackImageURL ?? detail.thumbnailURL, placeholderSymbol: "fork.knife")
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.media, style: .continuous))
            // One column at accessibility sizes, so labels and values wrap whole words.
            DynamicGridLayout(minCellWidth: dynamicTypeSize.isAccessibilitySize ? 320 : 150, maxColumns: 3, spacing: HassTokens.Spacing.s) {
                ForEach(RecipeFormatting.facts(detail)) { fact in
                    FactTile(fact: fact)
                }
            }
            if detail.capabilities.general == .none {
                Notice("Servings, time, difficulty, and equipment are not available in the cached Cookidoo metadata.")
            } else {
                FactList(title: "Devices", items: detail.general.devices)
                FactList(title: "Optional Devices", items: detail.general.optionalDevices)
                FactList(title: "Additional Equipment", items: detail.general.equipment)
            }
            if let url = detail.source.canonicalURL {
                ExternalLinkButton(title: detail.source.isCookidoo ? "Open in Cookidoo" : "Open Source Recipe", url: url)
                    .accessibilityIdentifier("recipe.openSource")
            }
        }
    }
}

/// A prominent button that opens a web page through `openURL`, in the Food action tint (``FoodStyle/action``).
struct ExternalLinkButton: View {
    var title: String
    var url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(FoodStyle.action)
        .accessibilityAddTraits(.isLink)
    }
}

/// One fact: symbol, label and value (web `StatusPill`).
struct FactTile: View {
    let fact: RecipeFormatting.Fact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The symbol goes above the text at accessibility sizes, leaving the text the tile's full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: HassTokens.Spacing.s))
        layout {
            Image(systemName: fact.symbol)
                .foregroundStyle(HassTokens.Ink.secondary)
                .frame(minWidth: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.label).font(.caption).foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fact.value).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.label)
        .accessibilityValue(fact.spokenValue ?? fact.value)
    }
}

/// A titled bullet list; nothing when empty.
struct FactList: View {
    var title: String
    var items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text(title).font(.headline).foregroundStyle(HassTokens.Ink.primary).accessibilityAddTraits(.isHeader)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                }
            }
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(HassTokens.Ink.secondary).accessibilityHidden(true)
            configuration.title.foregroundStyle(HassTokens.Ink.primary)
        }
    }
}

/// A quiet status line (web `.notice` with `role="status"`).
struct Notice: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(HassTokens.Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ingredients

/// Ingredient checklist with inventory state, and the grocery action (web `IngredientsTab`).
///
/// Rows are read-only here; the web's per-row grocery buttons, product picker and match feedback are a
/// later port (`.agents/pages/food/spec.md`).
struct RecipeIngredientsTab: View {
    let detail: RecipeDetail
    let model: RecipeDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
            if detail.capabilities.ingredients != .none, detail.ingredientsTruncated {
                Notice("This ingredient list is truncated.")
            }
            if detail.capabilities.ingredients == .none || detail.ingredients.isEmpty {
                ContentUnavailableView("No Ingredients Available", systemImage: "list.bullet",
                                       description: Text("Ingredient details are not available for this recipe."))
            } else {
                ForEach(RecipeFormatting.ingredientSections(detail)) { section in
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.headline)
                                .foregroundStyle(section.headingIsGenerated ? HassTokens.Ink.secondary : HassTokens.Ink.primary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.ingredients) { ingredient in
                            IngredientRow(detail: detail, ingredient: ingredient, checklist: detail.capabilities.ingredients == .checklist)
                        }
                    }
                }
            }
            GroceryAction(model: model)
        }
    }
}

/// One ingredient: status mark, title with amount, chips, source text and match (web `CheckboxRow` + `IngredientSubtitle`).
struct IngredientRow: View {
    let detail: RecipeDetail
    let ingredient: RecipeDetail.Ingredient
    var checklist: Bool

    var body: some View {
        let onHand = RecipeFormatting.isOnHand(ingredient)
        HStack(alignment: .top, spacing: HassTokens.Spacing.m) {
            if checklist {
                Image(systemName: onHand ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(onHand ? Color.green : HassTokens.Ink.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                Text(RecipeFormatting.title(ingredient))
                    .font(.body.weight(.medium))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if checklist {
                    ChipFlow(chips: RecipeFormatting.chips(detail, ingredient))
                } else {
                    let notes = [ingredient.optional == true ? "Optional" : nil, RecipeFormatting.quantityNote(detail, ingredient)].compactMap { $0 }
                    if !notes.isEmpty { ChipFlow(chips: notes) }
                }
                if let source = RecipeFormatting.sourceDetail(ingredient) {
                    Text("Source: \(source)").font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let match = ingredient.closestMatchLabel {
                    Text("Matched as \(match)").font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(HassTokens.Spacing.m)
        .frame(minHeight: HassTokens.minTarget)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecipeFormatting.title(ingredient))
        .accessibilityValue(checklist ? (onHand ? "On hand" : "Not on hand") : "")
        .accessibilityHint(RecipeFormatting.accessibilityDetails(detail, ingredient))
        .accessibilityIdentifier("recipe.ingredient.\(ingredient.position)")
    }
}

/// Small capsules that wrap onto new lines.
struct ChipFlow: View {
    var chips: [String]

    var body: some View {
        FlowLayout(spacing: HassTokens.Spacing.xs) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.caption)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .padding(.horizontal, HassTokens.Spacing.s)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.16), in: Capsule())
            }
        }
    }
}

/// Lays children left to right, wrapping to new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], itemWidth, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// "Add Missing Ingredients to Groceries" with its disabled reason, progress and result (web `RecipeGroceryAction`).
struct GroceryAction: View {
    let model: RecipeDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            switch model.grocery {
            case let .added(message):
                HStack(spacing: HassTokens.Spacing.s) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).accessibilityHidden(true)
                    Text("Added to Groceries").foregroundStyle(HassTokens.Ink.primary)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recipe.grocery.added")
                Text(message).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("recipe.grocery.message")
            default:
                Button {
                    model.addMissingToGroceries()
                } label: {
                    HStack(spacing: HassTokens.Spacing.s) {
                        if model.grocery == .adding {
                            ProgressView()
                        } else {
                            Image(systemName: "cart.badge.plus")
                        }
                        Text("Add Missing Ingredients to Groceries")
                    }
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(FoodStyle.action)
                .disabled(model.groceryDisabledReason != nil)
                .accessibilityIdentifier("recipe.grocery.add")
                if let reason = model.groceryDisabledReason {
                    Text(reason).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityIdentifier("recipe.grocery.reason")
                }
                if case let .failed(message) = model.grocery {
                    HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red).accessibilityHidden(true)
                        Text(message).foregroundStyle(HassTokens.Ink.primary).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: \(message)")
                    .accessibilityIdentifier("recipe.grocery.error")
                }
            }
        }
        .padding(.top, HassTokens.Spacing.s)
        .onChange(of: model.grocery) { _, state in
            #if os(iOS)
            switch state {
            case let .added(message): UIAccessibility.post(notification: .announcement, argument: "Added to groceries. \(message)")
            case let .failed(message): UIAccessibility.post(notification: .announcement, argument: message)
            default: break
            }
            #endif
        }
    }
}

// MARK: - Instructions

/// Numbered steps in groups, or the Cookidoo link (web `InstructionsTab`).
struct RecipeInstructionsTab: View {
    let detail: RecipeDetail

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
            if detail.capabilities.instructions == .externalLink {
                if let url = detail.instructions.fallbackURL ?? detail.source.canonicalURL {
                    VStack(spacing: HassTokens.Spacing.m) {
                        Image(systemName: "arrow.up.right.square").font(.largeTitle).foregroundStyle(HassTokens.Ink.secondary)
                            .accessibilityHidden(true)
                        Text("Instructions are on Cookidoo").font(.headline).foregroundStyle(HassTokens.Ink.primary)
                        Text("Official Cookidoo step text stays on Cookidoo and is not stored or shown here.")
                            .font(.subheadline).foregroundStyle(HassTokens.Ink.secondary).multilineTextAlignment(.center)
                        ExternalLinkButton(title: "Open in Cookidoo", url: url)
                            .accessibilityIdentifier("recipe.openCookidoo")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("Instructions Link Unavailable", systemImage: "link",
                                           description: Text("The external instruction link is not available."))
                }
            } else if detail.capabilities.instructions == .local, detail.instructions.available {
                if detail.instructions.truncated { Notice("These instructions are truncated.") }
                ForEach(Array(detail.instructions.groups.enumerated()), id: \.element.id) { index, group in
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                        if let heading = RecipeFormatting.sectionHeading(group.label, index: index, count: detail.instructions.groups.count) {
                            Text(heading.label)
                                .font(.headline)
                                .foregroundStyle(heading.generated ? HassTokens.Ink.secondary : HassTokens.Ink.primary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.steps) { step in
                            HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
                                Text("\(step.number).")
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(HassTokens.Ink.secondary)
                                Text(step.text)
                                    .foregroundStyle(HassTokens.Ink.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Step \(step.number). \(step.text)")
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Instructions Available", systemImage: "list.number",
                                       description: Text("Instructions are not available for this recipe."))
            }
        }
    }
}
