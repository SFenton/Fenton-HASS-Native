import HassCore
import HassDesign
import SwiftUI

/// The sheet a Home status chip opens. Lights is interactive; the others list their entities
/// read-only until their full ports land (`.agents/pages/home/ios.md`).
struct ChipSheet: View {
    var kind: HomeConfig.ChipSheet
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    /// Grows with Dynamic Type so tiles drop to fewer columns instead of clipping their titles.
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .lights:
            ScrollView {
                DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 6) {
                    ForEach(HomeConfig.lightGroups) { group in
                        let state = store.entity(group.toggleEntityId).state
                        GlassTile(
                            title: group.title,
                            subtitle: state.map { $0.isUnavailable ? "Unavailable" : ($0.state == "on" ? "On" : "Off") },
                            symbol: "lightbulb",
                            tint: HassTokens.Tint.light,
                            isActive: state?.state == "on",
                            isUnavailable: state?.isUnavailable ?? true
                        ) {
                            Task { try? await connection.toggle(group.toggleEntityId) }
                        }
                        .accessibilityIdentifier("lights.group.\(group.toggleEntityId)")
                    }
                }
                .padding()
            }
        default:
            List(memberStates) { entity in
                LabeledContent(entity.friendlyName, value: entity.state.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            .overlay {
                if memberStates.isEmpty {
                    ContentUnavailableView("Nothing to show", systemImage: "questionmark.circle")
                }
            }
        }
    }

    private var chip: HomeConfig.StatusChip? {
        HomeConfig.statusChips.first { $0.sheet == kind }
    }

    private var title: String { chip?.title ?? "" }

    /// The chip entity's group members (its `entity_id` attribute), or the entity itself.
    private var memberStates: [EntityState] {
        guard let chip, let entity = store.entity(chip.entityId).state else { return [] }
        let ids = entity.attributes["entity_id"]?.array?.compactMap(\.string) ?? [chip.entityId]
        return ids.compactMap { store.entity($0).state }
    }
}
