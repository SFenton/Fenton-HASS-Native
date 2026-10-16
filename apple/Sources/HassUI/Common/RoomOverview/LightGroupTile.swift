import HassCore
import HassDesign
import SwiftUI

/// One light or light group: a brightness tile when the light dims, else a power tile. Both send explicit
/// `turn_on` / `turn_off` (``LightControl``), never `toggle`: Presence Based Lighting's Presence Lock reverts
/// toggles. Room detail pages and room Lights sheets use it per light and for the room's group light.
struct LightGroupTile: View {
    var title: String
    var entityId: String
    var state: EntityState?
    var send: (LightControl.Command) -> Void

    /// A tile for any light or switch.
    init(title: String, entityId: String, state: EntityState?, send: @escaping (LightControl.Command) -> Void) {
        self.title = title
        self.entityId = entityId
        self.state = state
        self.send = send
    }

    var body: some View {
        let id = entityId
        let unavailable = state?.isUnavailable ?? true
        if LightControl.isDimmable(state) {
            BrightnessTile(
                title: title,
                tint: HassTokens.Tint.light,
                fillTint: LightControl.rgb(of: state).map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
                percent: LightControl.percent(of: state),
                isUnavailable: unavailable,
                onPower: { send(LightControl.power(id, on: $0)) },
                onBrightness: { send(LightControl.brightness(id, percent: Double($0))) }
            )
        } else {
            let on = state?.state == "on"
            GlassTile(
                title: title,
                subtitle: state.map { $0.isUnavailable ? "Unavailable" : (on ? "On" : "Off") },
                symbol: "lightbulb",
                family: .lights,
                isActive: on,
                isUnavailable: unavailable
            ) {
                send(LightControl.flip(id, shownOn: on))
            }
        }
    }
}
