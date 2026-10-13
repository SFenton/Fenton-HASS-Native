import HassCore
import HassDesign
import SwiftUI

/// The overview's room cards in one equal-height grid, sections headed inside it so every card matches the tallest
/// (a room name that wraps lifts them all).
struct RoomOverviewGrid: View {
    var kind: RoomOverviewKind
    var onSelect: (RoomGroup) -> Void
    @Environment(EntityStore.self) private var store
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 6, equalRowHeights: true) {
            if kind == .airQuality {
                RoomOverviewHeading(title: "Rooms").gridHeader()
                ForEach(RoomOverview.airQualityRooms) { room in
                    AirQualityRoomTile(room: room)
                }
            } else {
                ForEach(RoomOverview.sections(kind, read: read)) { section in
                    RoomOverviewHeading(title: section.title)
                        .gridHeader()
                        .accessibilityIdentifier("overview.\(kind.rawValue).section.\(section.title)")
                    ForEach(section.groups, id: \.room) { group in
                        RoomOverviewTile(kind: kind, group: group) { onSelect(group) }
                    }
                }
            }
        }
        .equalHeightTiles()
    }

    private func read(_ id: String) -> EntityState? { store.entity(id).state }
}
