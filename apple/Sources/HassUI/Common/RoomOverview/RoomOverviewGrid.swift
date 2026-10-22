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
                RoomSectionHeader(title: "Rooms", inSheet: true).gridHeader()
                ForEach(RoomOverview.airQualityRooms) { room in
                    AirQualityRoomTile(room: room)
                }
            } else {
                ForEach(sections) { section in
                    RoomSectionHeader(title: section.title, inSheet: true)
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

    /// Shared screenshots hide who is home, so redacted occupancy lists every room under one heading.
    private var sections: [RoomOverviewSection] {
        if ScreenshotPrivacy.isRedacting, kind == .occupancy {
            return [RoomOverviewSection(title: "Rooms", groups: RoomOverview.groups(kind))]
        }
        return RoomOverview.sections(kind, read: read)
    }

    private func read(_ id: String) -> EntityState? { store.entity(id).state }
}
