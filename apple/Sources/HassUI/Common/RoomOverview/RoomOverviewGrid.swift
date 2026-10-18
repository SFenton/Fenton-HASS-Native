import HassCore
import HassDesign
import SwiftUI

/// The overview's room cards in one equal-height grid, sections headed inside it so every card matches the tallest
/// (a room name that wraps lifts them all).
struct RoomOverviewGrid: View {
    var kind: RoomOverviewKind
    /// When set, each room tile is the source of a zoom into its page (``SwiftUICore/View/zoomSource(id:in:cornerRadius:)``);
    /// the sheet's destination names the same ids in the same namespace.
    var zoomNamespace: Namespace.ID?
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
                            .zoomed(from: zoomNamespace, id: group.room)
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

private extension View {
    /// The tile as a zoom source when the sheet has a namespace (the tile's own 22 pt radius, so the morph is clean).
    @ViewBuilder
    func zoomed(from namespace: Namespace.ID?, id: String) -> some View {
        if let namespace {
            zoomSource(id: id, in: namespace, cornerRadius: HassTokens.Radius.tile)
        } else {
            self
        }
    }
}
