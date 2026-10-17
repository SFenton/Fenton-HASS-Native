import HassCore
import HassDesign
import SwiftUI

// MARK: - Presentations

/// The recipe detail as a sheet (web `RecipeDetailModal`): large detent, its own navigation bar with the circle-x
/// Close, the centred title over "8 of 9 Ingredients" (iOS 26), and the sections in the bottom glass bar (direction G,
/// Sheets; mockups n6 recipe detail and ingredients).
struct RecipeDetailSheet: View {
    let model: RecipeDetailModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RecipeDetailContent(model: model)
                .modalChrome()
                .toolbar { SheetCloseItem(identifier: "recipe.done") { dismiss() } }
        }
        .hassSheet(.page)
        // Explicitly full height (owner, 2026-10-16): other sheets size to their content, but a recipe is a page to read.
        .presentationDetents([.large])
    }
}

/// The recipe detail in the trailing half of a split (iPad and unfolded iPhone Duo landscape).
struct RecipeDetailPane: View {
    let model: RecipeDetailModel
    var onClose: () -> Void

    /// Its own header rather than a `NavigationStack`: the pane sits inside the Food stack's Recipes page,
    /// and a nested stack showed nothing on iPad landscape (2026-10-11).
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
                Text(model.detail?.title ?? model.recipe.title)
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                SheetCloseButton(identifier: "recipe.close", action: onClose)
                    .frame(minWidth: HassTokens.minTarget, minHeight: HassTokens.minTarget)
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.s)
            Divider()
            RecipeDetailContent(model: model, setsNavigationTitle: false)
                // The pane's lists keep the sheet's `#2C2C2E` cells rather than the page module.
                .environment(\.tileSurface, .sheet)
        }
        .background(.background)
        .overlay(alignment: .leading) { Divider() }
        .id(model.recipe.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe.pane")
    }
}

// MARK: - Content

/// The selected tab under the title, with the tabs in the bottom glass section bar (web `RECIPE_DETAIL_TABS`: General,
/// Ingredients, Instructions; `.agents/patterns/modal-sheet.md`).
struct RecipeDetailContent: View {
    @Bindable var model: RecipeDetailModel
    /// False in the split pane, whose page title stays "Recipes".
    var setsNavigationTitle = true
    /// The scroll view's visible height, so Instructions can centre in it.
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Loading recipe details")
                    .progressViewStyle(.arc)
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
        .modifier(DetailTitle(title: model.detail?.title ?? model.recipe.title, subtitle: subtitle, isEnabled: setsNavigationTitle))
        .onAppear { model.load() }
        .overlay(alignment: .bottomTrailing) { DetailDebugMarker(model: model) }
    }

    /// "8 of 9 Ingredients" under the title, when the card counted any.
    private var subtitle: String? {
        model.recipe.requiredTotal > 0 ? model.recipe.coverageText : nil
    }

    private func loaded(_ detail: RecipeDetail) -> some View {
        // Instructions that fit the sheet sit in its vertical centre (owner, 2026-10-16); longer ones scroll from the top.
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                switch model.tab {
                case .general: RecipeGeneralTab(detail: detail, fallbackImageURL: model.recipe.imageURL)
                case .ingredients: RecipeIngredientsTab(detail: detail, model: model)
                case .instructions: RecipeInstructionsTab(detail: detail)
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
            .frame(minHeight: model.tab == .instructions ? viewportHeight : nil, alignment: .center)
        }
        .scrollBounceBehavior(model.tab == .instructions ? .basedOnSize : .automatic)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { viewportHeight = $0 }
        .scrollTelemetry("Recipe Detail")
        .accessibilityIdentifier("recipe.scroll")
        .modalTabBar(RecipeDetailModel.Tab.allCases, label: "Recipe sections", title: \.title,
                     selection: $model.tab, identifier: "recipe.tabs")
    }
}

// MARK: - General

/// Hero image, facts, equipment and the source link (web `GeneralTab`): the photo in a 26 pt card, then the facts as
/// an inset list with leading glyphs and trailing values (mockup n6 recipe detail).
struct RecipeGeneralTab: View {
    let detail: RecipeDetail
    var fallbackImageURL: URL?

    var body: some View {
        let facts = RecipeFormatting.facts(detail)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            RemoteImage(url: detail.primaryImageURL ?? detail.thumbnailURL, fallbackURL: fallbackImageURL ?? detail.thumbnailURL, placeholderSymbol: "fork.knife")
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(HassTokens.Surface.sheetCell)
                .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.module))
            if !facts.isEmpty {
                ModuleList {
                    ForEach(facts) { fact in
                        RecipeFactRow(fact: fact)
                    }
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
                ModuleList {
                    RecipeLinkRow(title: detail.source.isCookidoo ? "Open in Cookidoo" : "Open Source Recipe", url: url)
                        .accessibilityIdentifier("recipe.openSource")
                }
            }
        }
    }
}

/// The tab's one primary action that opens a web page through `openURL` ("Open in Cookidoo" on Instructions): a
/// ``PrimaryButton`` with the link trait.
struct ExternalLinkButton: View {
    var title: String
    var url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        PrimaryButton(title, systemImage: "arrow.up.right.square") { openURL(url) }
            .accessibilityAddTraits(.isLink)
    }
}

/// Debug builds with `FENTON_FOOD_DEBUG=1` (live journeys only): exposes the model's identity, tab and body
/// count so a journey can tell a rebuilt model from a lost tap.
struct DetailDebugMarker: View {
    let model: RecipeDetailModel

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_FOOD_DEBUG"] == "1" {
            Text("model \(ObjectIdentifier(model).hashValue) tab \(model.tab.rawValue)")
                .font(.caption2)
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityIdentifier("recipe.debug")
        }
        #endif
    }
}

/// The detail's inline navigation title and subtitle, when it owns the navigation bar (the sheet).
struct DetailTitle: ViewModifier {
    var title: String
    var subtitle: String?
    var isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationTitle(title).inlineNavigationTitle().sheetSubtitle(subtitle)
        } else {
            content
        }
    }
}

/// A titled inset list of names (devices, equipment); nothing when empty.
struct FactList: View {
    var title: String
    var items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                RecipeSectionHeader(title)
                    .padding(.horizontal, HassTokens.Spacing.l)
                ModuleList(hasGlyphs: false) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .foregroundStyle(HassTokens.Ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, HassTokens.Spacing.l)
                            .padding(.vertical, HassTokens.Spacing.m)
                            .frame(maxWidth: .infinity, minHeight: RecipeRowMetrics.minHeight, alignment: .leading)
                    }
                }
            }
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

/// Ingredient checklist with inventory state, and the grocery action (web `IngredientsTab`): each group an inset list
/// under its header, rows marked with a green check or an empty circle, and the inventory match in small capsules
/// (mockup n6 recipe ingredients).
///
/// Rows are read-only here; the web's per-row grocery buttons, product picker and match feedback are a
/// later port (`.agents/pages/food/spec.md`).
struct RecipeIngredientsTab: View {
    let detail: RecipeDetail
    let model: RecipeDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            if detail.capabilities.ingredients != .none, detail.ingredientsTruncated {
                Notice("This ingredient list is truncated.")
            }
            if detail.capabilities.ingredients == .none || detail.ingredients.isEmpty {
                ContentUnavailableView("No Ingredients Available", systemImage: "list.bullet",
                                       description: Text("Ingredient details are not available for this recipe."))
            } else {
                let checklist = detail.capabilities.ingredients == .checklist
                ForEach(RecipeFormatting.ingredientSections(detail)) { section in
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                        if let heading = section.heading {
                            RecipeSectionHeader(heading, isQuiet: section.headingIsGenerated)
                                .padding(.horizontal, HassTokens.Spacing.l)
                        }
                        ModuleList(hasGlyphs: checklist) {
                            ForEach(section.ingredients) { ingredient in
                                IngredientRow(detail: detail, ingredient: ingredient, checklist: checklist)
                            }
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
    /// The mark's column, scaled like ``ModuleList``'s hairline inset so the title starts where the hairline does.
    @ScaledMetric(relativeTo: .body) private var glyphWidth = RecipeRowMetrics.glyph

    var body: some View {
        let onHand = RecipeFormatting.isOnHand(ingredient)
        HStack(alignment: .top, spacing: RecipeRowMetrics.gap) {
            if checklist {
                Image(systemName: Self.mark(ingredient, onHand: onHand))
                    .font(.title3)
                    .foregroundStyle(onHand ? Color.green : HassTokens.Ink.secondary)
                    .frame(width: glyphWidth)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text(RecipeFormatting.title(ingredient))
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: RecipeRowMetrics.minHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecipeFormatting.title(ingredient))
        .accessibilityValue(checklist ? (onHand ? "On hand" : "Not on hand") : "")
        .accessibilityHint(RecipeFormatting.accessibilityDetails(detail, ingredient))
        .accessibilityIdentifier("recipe.ingredient.\(ingredient.position)")
    }

    /// The row's mark: a filled check when on hand, a question mark when EverShelf is unsure of the match (and nobody
    /// overrode it), else an empty circle. The spoken value stays "On hand" or "Not on hand".
    static func mark(_ ingredient: RecipeDetail.Ingredient, onHand: Bool) -> String {
        if onHand { return "checkmark.circle.fill" }
        if ingredient.overrideAvailability == nil, ingredient.inventoryState == .uncertain { return "questionmark.circle" }
        return "circle"
    }
}

/// Small capsules that wrap onto new lines.
struct ChipFlow: View {
    var chips: [String]

    var body: some View {
        FlowLayout(spacing: HassTokens.Spacing.s) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .padding(.horizontal, HassTokens.Spacing.s)
                    .padding(.vertical, HassTokens.Spacing.xs)
                    .background(Color.secondary.opacity(0.16), in: Capsule())
            }
        }
    }
}

/// "Add to Grocery List", the sheet's one ``PrimaryButtonStyle`` button, with its description (or the reason it is
/// disabled), progress and result (web `RecipeGroceryAction`, which says "Add Missing Ingredients to Groceries"; the
/// owner renamed it on 2026-10-16).
struct GroceryAction: View {
    let model: RecipeDetailModel

    /// The button's title.
    static let title = "Add to Grocery List"
    /// What the button does, under it while it can run (a disabled button shows its reason instead).
    static let explanation = "Adds the missing ingredients for this recipe to your shopping list."

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            switch model.grocery {
            case let .added(message):
                HStack(spacing: HassTokens.Spacing.s) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green).accessibilityHidden(true)
                    Text("Added to Grocery List").foregroundStyle(HassTokens.Ink.primary)
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
                            ArcSpinner(.inline).accessibilityHidden(true)
                        } else {
                            Image(systemName: "cart.badge.plus").accessibilityHidden(true)
                        }
                        Text(Self.title)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.groceryDisabledReason != nil)
                .accessibilityIdentifier("recipe.grocery.add")
                if let reason = model.groceryDisabledReason {
                    Text(reason).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recipe.grocery.reason")
                } else {
                    Text(Self.explanation).font(.footnote).foregroundStyle(HassTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recipe.grocery.description")
                }
                if case let .failed(message) = model.grocery {
                    InlineAlert(message, severity: .error)
                        .accessibilityIdentifier("recipe.grocery.error")
                }
            }
        }
        .onChange(of: model.grocery) { _, state in
            #if os(iOS)
            switch state {
            case let .added(message): UIAccessibility.post(notification: .announcement, argument: "Added to grocery list. \(message)")
            case let .failed(message): UIAccessibility.post(notification: .announcement, argument: message)
            default: break
            }
            #endif
        }
    }
}

// MARK: - Instructions

/// Numbered steps in groups, each an inset list under its header, or the Cookidoo link (web `InstructionsTab`).
struct RecipeInstructionsTab: View {
    let detail: RecipeDetail

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
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
                    VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                        if let heading = RecipeFormatting.sectionHeading(group.label, index: index, count: detail.instructions.groups.count) {
                            RecipeSectionHeader(heading.label, isQuiet: heading.generated)
                                .padding(.horizontal, HassTokens.Spacing.l)
                        }
                        ModuleList(hasGlyphs: false) {
                            ForEach(group.steps) { step in
                                RecipeStepRow(step: step)
                            }
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
