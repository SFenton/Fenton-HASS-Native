import HassCore
import HassDesign
import SwiftUI

/// One room in the Air Quality sheet: AQI and PM2.5, its glyph and rim in the room's AQI colour (the AQI scale is the
/// information, so it is not swapped for the air family's teal); read-only like the web's.
struct AirQualityRoomTile: View {
    var room: AirQualityRoom
    @Environment(EntityStore.self) private var store

    var body: some View {
        let read: RoomOverview.Read = { store.entity($0).state }
        GlassTile(
            title: room.title,
            subtitle: RoomFormat.airSummary(aqi: read(room.aqiEntityId), pm25: read(room.pm25EntityId)),
            symbol: SymbolMap.symbol(for: "mdi:blur"),
            tint: RoomOverview.airQualityColor(room, read: read).color,
            isActive: true,
            kind: .state
        )
        .accessibilityIdentifier("overview.airQuality.room.\(room.title)")
    }
}
