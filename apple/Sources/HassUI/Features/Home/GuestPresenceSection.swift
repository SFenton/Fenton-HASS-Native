import HassCore
import HassDesign
import SwiftUI

/// Guest stays (web `GuestPresenceSecuritySection`, first pass: the stay toggles only).
/// Shown only while a guest toggle is on, matching the web.
struct GuestPresenceSection: View {
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection

    var body: some View {
        let anyGuests = HomeConfig.guestToggles.contains { store.entity($0.entityId).state?.state == "on" }
        if anyGuests {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text("Guests Staying Over")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Guest mode skips some away automations. Review security, climate, and auto-clean controls before leaving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ControlTileGrid {
                    ForEach(HomeConfig.guestToggles) { toggle in
                        let state = store.entity(toggle.entityId).state
                        GlassTile(
                            title: toggle.title,
                            subtitle: state?.state == "on" ? "Guests staying" : "No guests",
                            symbol: SymbolMap.symbol(for: toggle.icon),
                            tint: HassTokens.Tint.presence,
                            isActive: state?.state == "on",
                            isUnavailable: state?.isUnavailable ?? true
                        ) {
                            Task { try? await connection.toggle(toggle.entityId) }
                        }
                    }
                }
            }
        }
    }
}

/// A `DynamicGridLayout` sized for small control tiles.
struct ControlTileGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        DynamicGridLayout(minCellWidth: 110, maxColumns: 6) { content }
    }
}
