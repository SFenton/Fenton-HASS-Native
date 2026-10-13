import HassCore
import HassDesign
import SwiftUI

/// One room card in an overview: the room's state, washed with its color while active, opening its detail page.
struct RoomOverviewTile: View {
    var kind: RoomOverviewKind
    var group: RoomGroup
    var action: () -> Void
    @Environment(EntityStore.self) private var store

    var body: some View {
        let active = RoomOverview.isActive(kind, group, read: read)
        let redact = ScreenshotPrivacy.isRedacting && kind == .occupancy
        GlassTile(
            title: group.room,
            subtitle: redact ? "Hidden" : RoomOverview.cardSubtitle(kind, group, read: read),
            symbol: symbol(active: active && !redact),
            tint: RoomOverviewStyle.tint(kind),
            isActive: active && !redact,
            kind: .navigate,
            wash: active && !redact ? RoomOverview.cardColor(kind, group, read: read).color.opacity(0.45) : nil,
            action: action
        )
        .accessibilityHint("Opens \(RoomOverview.detailTitle(kind, group))")
        .accessibilityIdentifier("overview.\(kind.rawValue).room.\(group.room)")
    }

    private func symbol(active: Bool) -> String {
        switch kind {
        case .lights: group.items.count > 1 ? "lightbulb.2" : "lightbulb"
        case .climate: SymbolMap.symbol(for: RoomOverview.roomIcon(group.room) ?? "mdi:thermometer")
        case .occupancy: SymbolMap.symbol(for: active ? "mdi:motion-sensor" : "mdi:motion-sensor-off")
        case .contacts: RoomOverviewStyle.contactSymbol(window: RoomOverview.isWindowGroup(group), open: active)
        case .airQuality: SymbolMap.symbol(for: "mdi:blur")
        }
    }

    private func read(_ id: String) -> EntityState? { store.entity(id).state }
}
