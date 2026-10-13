import HassCore
import HassDesign
import SwiftUI

/// A room pushed from an overview sheet: the group's title, its live summary and its tiles (web room detail inside
/// `ModalSheet`, title `group.title`, subtitle `roomDetailSubtitle`).
struct RoomGroupDetailPage: View {
    var kind: RoomOverviewKind
    var group: RoomGroup
    /// Closes the whole sheet from this page, so Done stays in the bar at every depth (HIG: Sheets).
    var onDone: (() -> Void)?
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.roomServiceCaller) private var callerOverride
    /// Optimistic light power (`.agents/patterns/optimistic-actions.md`): a tap shows at once, a rejected call rolls
    /// back, and any live change wins (Presence Based Lighting may revert a light), so lights clear on `.liveChange`.
    @State private var lights: OptimisticActions?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                Text(ScreenshotPrivacy.isRedacting && kind == .occupancy ? "Hidden" : RoomOverview.detailSubtitle(kind, group, read: read))
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .accessibilityIdentifier("overview.detail.subtitle")
                RoomGroupDetail(kind: kind, group: group, read: read, send: send)
            }
            .padding(HassTokens.Spacing.l)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(RoomOverview.detailTitle(kind, group))
        .inlineNavigationTitle()
        .accessibilityIdentifier("overview.detail.\(group.room)")
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
        }
        .onAppear {
            guard kind == .lights, lights == nil, let caller = callerOverride ?? connection else { return }
            let ids = group.items.map(\.entityId) + [group.entityId].compactMap { $0 }
            lights = OptimisticActions(store: store, rules: Dictionary(ids.map { ($0, .liveChange) }) { first, _ in first },
                                       caller: caller)
        }
    }

    /// The live entity, with a pending light power shown in place of its state.
    private func read(_ id: String) -> EntityState? {
        guard var entity = store.entity(id).state else { return nil }
        if let shown = lights?.shown(id) { entity.state = shown }
        return entity
    }

    private func send(_ command: LightControl.Command) {
        // Brightness above 0 and turn_on both show the light on; turn_off shows it off.
        let shown = command.service == "turn_off" ? "off" : "on"
        lights?.perform(command.domain, command.service, data: command.serviceData,
                        showing: [OptimisticIntent(command.entityId, value: shown)])
    }
}
