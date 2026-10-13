import HassCore
import HassDesign
import SwiftUI

/// One room in the Air Quality sheet: AQI and PM2.5, washed with the room's AQI color; read-only like the web's.
struct AirQualityRoomTile: View {
    var room: AirQualityRoom
    @Environment(EntityStore.self) private var store

    var body: some View {
        let read: RoomOverview.Read = { store.entity($0).state }
        GlassTile(
            title: room.title,
            subtitle: RoomFormat.airSummary(aqi: read(room.aqiEntityId), pm25: read(room.pm25EntityId)),
            symbol: SymbolMap.symbol(for: "mdi:blur"),
            tint: RoomOverviewStyle.tint(.airQuality),
            isActive: true,
            kind: .state,
            wash: RoomOverview.airQualityColor(room, read: read).color.opacity(0.45)
        )
        .accessibilityIdentifier("overview.airQuality.room.\(room.title)")
    }
}
