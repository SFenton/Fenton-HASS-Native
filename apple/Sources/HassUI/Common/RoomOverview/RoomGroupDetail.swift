import HassCore
import HassDesign
import SwiftUI

/// A room's lights, temperatures and vents, presence sensors or doors and windows, shared by Home's overview detail
/// pages and the room pages' group sheets (web `RoomLightDetailCards`, `RoomClimateDetailCards`,
/// `RoomOccupancyDetailCards`, `RoomContactDetailCards`).
///
/// Every run of tiles is one equal-height grid. Lights send explicit `turn_on` / `turn_off` through
/// ``LightGroupTile``; the sensor tiles are read-only.
struct RoomGroupDetail: View {
    var kind: RoomOverviewKind
    var group: RoomGroup
    /// Room pages hide the occupancy and contact headings, where the sheet's title already names them.
    var showsHeadings = true
    var read: RoomOverview.Read
    var send: (LightControl.Command) -> Void
    @Environment(\.householdViewer) private var viewer
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        let sections = RoomOverview.detailSections(kind, group, showsHeadings: showsHeadings)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            if kind == .lights {
                // "Lights", then the whole room at once, then each light (web `RoomLightDetailHeader` with its
                // group slider above `RoomLightDetailCards`).
                if let title = sections.first?.title { RoomSectionHeader(title: title, inSheet: true) }
                if let groupLight = RoomOverview.groupLightEntityId(group) {
                    LightGroupTile(title: RoomOverview.detailTitle(kind, group), entityId: groupLight, state: read(groupLight), send: send)
                        .accessibilityIdentifier("room.lightGroup.\(groupLight)")
                }
            }
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
                ForEach(sections) { section in
                    if kind != .lights, let title = section.title { RoomSectionHeader(title: title, inSheet: true).gridHeader() }
                    ForEach(section.items) { item in tile(item) }
                }
            }
            .equalHeightTiles()
        }
    }

    @ViewBuilder
    private func tile(_ item: RoomGroupItem) -> some View {
        let entity = read(item.entityId)
        switch kind {
        case .lights:
            LightGroupTile(title: item.title(for: viewer), entityId: item.entityId, state: entity, send: send)
                .accessibilityIdentifier("room.light.\(item.entityId)")
        case .climate:
            let vent = item.entityId.hasPrefix("cover.")
            sensorTile(item, subtitle: RoomOverview.climateText(entity), symbol: vent ? "fan" : "thermometer.medium",
                       family: vent ? .vents : .climate, active: false)
        case .occupancy:
            let occupied = RoomFormat.isOccupied(entity)
            sensorTile(item, subtitle: RoomFormat.occupancy(entity),
                       symbol: SymbolMap.symbol(for: occupied ? "mdi:motion-sensor" : "mdi:motion-sensor-off"),
                       family: .occupancy, active: occupied, redacts: true)
        case .contacts:
            let open = RoomFormat.isOpen(entity)
            sensorTile(item, subtitle: RoomFormat.contact(entity),
                       symbol: RoomOverviewStyle.contactSymbol(window: RoomFormat.isWindow(item), open: open),
                       family: .contact, active: open)
        case .airQuality:
            EmptyView()
        }
    }

    /// A read-only sensor tile (web `source-row` cards): filled with its family colour while active (occupied, open),
    /// else dark with the family glyph (direction G, Colour families). Temperatures and vents never fill.
    private func sensorTile(_ item: RoomGroupItem, subtitle: String, symbol: String, family: ColorFamily, active: Bool,
                            redacts: Bool = false) -> some View {
        let redact = redacts && ScreenshotPrivacy.isRedacting
        let entity = read(item.entityId)
        return GlassTile(
            title: item.title,
            subtitle: redact ? "Hidden" : subtitle,
            symbol: symbol,
            family: family,
            isActive: active && !redact,
            isUnavailable: RoomFormat.isUnavailable(entity),
            kind: .state
        )
        .accessibilityIdentifier("room.entity.\(item.entityId)")
    }
}
