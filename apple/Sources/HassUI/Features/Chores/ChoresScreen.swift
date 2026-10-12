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
    var body: some View {
        TodoPageView(page: ChoresConfig.chores) {
            ChoreQuickLinks()
        }
        .navigationTitle("Chores")
        .navigationDestination(for: ChoresConfig.Page.self) { page in
            TodoPageScreen(page: page)
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

/// Quick links to the Chores sub-pages with their open counts (web `ChoresIntro`, a bounded 2–3 column grid).
struct ChoreQuickLinks: View {
    @Environment(ChoresModel.self) private var model
    @Environment(EntityStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text("Quick Links")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: 160, maxColumns: 3) {
                ForEach(ChoresConfig.quickLinks) { link in
                    let title = link.title(viewer: model.viewer)
                    let subtitle = link.subtitle { store.entity($0).state }
                    NavigationLink(value: link.page) {
                        QuickLinkFace(title: title, subtitle: subtitle,
                                      tint: Color(red: link.color.red / 255, green: link.color.green / 255, blue: link.color.blue / 255))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(subtitle)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("chores.link.\(link.id)")
                }
            }
        }
    }
}

/// A quick link tile: the shared glass tile face with the link's web color on its icon and border.
struct QuickLinkFace: View {
    var title: String
    var subtitle: String
    var tint: Color

    var body: some View {
        GlassTileFace(title: title, subtitle: subtitle, symbol: SymbolMap.symbol(for: "mdi:clipboard-list"),
                      tint: tint, isActive: true, showsChevron: true)
    }
}
