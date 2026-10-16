import HassCore
import HassDesign
import SwiftUI

/// The Chores tab (web `chores` route): quick links to Groceries and each list of chores, then the viewer's
/// own chores grouped by time of day. Spec: `.agents/pages/chores/spec.md`.
struct ChoresScreen: View {
    var body: some View {
        ChoresModelHost {
            ChoresContent()
        }
    }
}

/// The Chores tab's content once its model exists (the gallery hosts it over fixtures).
struct ChoresContent: View {
    @Environment(ChoresModel.self) private var model
    @Environment(EntityStore.self) private var store

    var body: some View {
        // Read here, during body: the stack builds destinations later, outside this view's update, where
        // reading the @Environment wrappers trapped (debug gallery, 2026-10-13).
        let model = model
        let store = store
        TodoPageView(page: ChoresConfig.chores) {
            ChoreQuickLinks()
        }
        .navigationTitle("Chores")
        .navigationDestination(for: ChoresConfig.Page.self) { page in
            // A pushed page takes its environment from the section's NavigationStack, above the
            // ChoresModelHost, so the model is handed on explicitly (without it every quick link crashed).
            // The store too: the app injects it above the stack, but the debug gallery injects it below.
            TodoPageScreen(page: page)
                .environment(model)
                .environment(store)
                .pageChrome()
        }
    }
}

/// A pushed todo page: Groceries, a resident's chores, Unassigned, Home Improvement, or the admin To-Do.
struct TodoPageScreen: View {
    var page: ChoresConfig.Page

    var body: some View {
        TodoPageView(page: page)
            .navigationTitle(page.title)
    }
}

/// The admin To-Do page opened from Settings, with its own model.
struct AdminTodoScreen: View {
    var body: some View {
        ChoresModelHost {
            TodoPageScreen(page: ChoresConfig.adminTodo)
        }
    }
}

/// Quick links to the Chores sub-pages with their open counts (web `ChoresIntro`, 2–3 columns). The grid grows to four
/// on iPad and stops there: four links fill four tracks and a wide Groceries closes the second row. Direction G mockup
/// n5-chores: dark tiles with the open count top-trailing, Groceries across the last row.
struct ChoreQuickLinks: View {
    @Environment(ChoresModel.self) private var model
    @Environment(EntityStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            PageSectionHeader("Quick Links")
            DynamicGridLayout(minCellWidth: 150, maxColumns: 4, equalRowHeights: true) {
                ForEach(Self.links) { link in
                    let title = link.title(viewer: model.viewer)
                    let subtitle = link.subtitle { store.entity($0).state }
                    let count = ChoresConfig.counts(for: link.page) { store.entity($0).state }.total
                    NavigationLink(value: link.page) {
                        QuickLinkFace(title: title, subtitle: subtitle, count: count, symbol: Self.symbol(for: link))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(subtitle)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("chores.link.\(link.id)")
                    // Five links: Groceries closes the grid across two tracks, in two, three or four columns alike.
                    .gridSpan(link.countsGroceries ? 2 : 1)
                }
            }
            .equalHeightTiles()
        }
    }

    /// The web's links with Groceries moved last, where it spans the final row (mockup n5-chores).
    static let links = ChoresConfig.quickLinks.filter { !$0.countsGroceries } + ChoresConfig.quickLinks.filter(\.countsGroceries)

    /// The link's glyph: a person for a resident's chores, a tray for Unassigned, a hammer for Home Improvement and
    /// a cart for Groceries (mockup n5-chores).
    static func symbol(for link: ChoresConfig.QuickLink) -> String {
        if link.countsGroceries { return "cart.circle.fill" }
        if link.resident != nil { return "person.crop.circle.fill" }
        if link.page == ChoresConfig.unassignedChores { return "tray.circle.fill" }
        return "hammer.circle.fill"
    }
}

/// A quick link tile: the shared dark tile face (chore lists are neutral grey; direction G, Open questions) with the
/// list's open count as a bold numeral in the top-trailing corner.
struct QuickLinkFace: View {
    var title: String
    var subtitle: String
    var count: Int
    var symbol: String

    var body: some View {
        GlassTileFace(title: title, subtitle: subtitle, symbol: symbol, tint: ColorFamily.neutral.glyph,
                      family: .neutral, isActive: false)
            .overlay(alignment: .topTrailing) {
                Text(count, format: .number)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(HassTokens.Ink.primary)
                    .padding(.top, HassTokens.Spacing.m - 2)
                    .padding(.trailing, HassTokens.Spacing.m + 2)
                    // The subtitle already speaks the counts.
                    .accessibilityHidden(true)
            }
    }
}
