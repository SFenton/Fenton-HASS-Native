import HassCore
import HassDesign
import SwiftUI

/// The sheet a Home status chip opens. Lights is interactive; the others list their entities
/// read-only until their full ports land (`.agents/pages/home/ios.md`).
struct ChipSheet: View {
    var kind: HomeConfig.ChipSheet
    @Environment(EntityStore.self) private var store
    /// Optional so the read-only sheets also open from the Security gallery, which has no connection.
    @Environment(HassConnection.self) private var connection: HassConnection?
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
                        LightGroupTile(group: group, state: store.entity(group.toggleEntityId).state) { command in
                            Task { try? await connection?.send(command) }
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

/// One light group in the Lights sheet: a brightness tile when the light dims, else a power tile.
/// Both send explicit `turn_on` / `turn_off` (``LightControl``), never `toggle`.
struct LightGroupTile: View {
    var group: HomeConfig.LightGroup
    var state: EntityState?
    var send: (LightControl.Command) -> Void

    var body: some View {
        let id = group.toggleEntityId
        let unavailable = state?.isUnavailable ?? true
        if LightControl.isDimmable(state) {
            BrightnessTile(
                title: group.title,
                tint: HassTokens.Tint.light,
                fillTint: LightControl.rgb(of: state).map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
                percent: LightControl.percent(of: state),
                isUnavailable: unavailable,
                onPower: { send(LightControl.power(id, on: $0)) },
                onBrightness: { send(LightControl.brightness(id, percent: Double($0))) }
            )
        } else {
            let on = state?.state == "on"
            GlassTile(
                title: group.title,
                subtitle: state.map { $0.isUnavailable ? "Unavailable" : (on ? "On" : "Off") },
                symbol: "lightbulb",
                tint: HassTokens.Tint.light,
                isActive: on,
                isUnavailable: unavailable
            ) {
                send(LightControl.flip(id, shownOn: on))
            }
        }
    }
}
