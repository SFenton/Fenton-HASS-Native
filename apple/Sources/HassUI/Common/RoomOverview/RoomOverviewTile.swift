import HassCore
import HassDesign
import SwiftUI

/// One room card in an overview: the room's state, opening its detail page. Direction G faces
/// (``RoomOverviewStyle/isFilled(_:active:)``): a room with lights on is the lit tile, an occupied room or one with a
/// door open fills with its family colour, and the rest stay dark with the family glyph.
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
            family: RoomOverviewStyle.family(kind),
            isActive: RoomOverviewStyle.isFilled(kind, active: active && !redact),
            kind: .navigate,
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
