import HassCore
import HassDesign
import SwiftUI

/// Tints and symbols shared by the overview and detail tiles.
enum RoomOverviewStyle {
    /// The icon tint for a kind's active tiles.
    static func tint(_ kind: RoomOverviewKind) -> Color {
        switch kind {
        case .lights: RoomTone.light.color
        case .climate: RoomTone.climate.color
        case .occupancy: RoomTone.presence.color
        case .contacts: RoomTone.contact.color
        case .airQuality: RoomTone.air.color
        }
    }

    /// Door or window, open or closed (web `ContactIcon`).
    static func contactSymbol(window: Bool, open: Bool) -> String {
        SymbolMap.symbol(for: window ? (open ? "mdi:window-open" : "mdi:window-closed") : (open ? "mdi:door-open" : "mdi:door"))
    }
}
