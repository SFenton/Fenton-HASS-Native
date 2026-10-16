import HassCore
import HassDesign
import SwiftUI

/// One tile of the Security page's Doors (and Mach-E) section: a lock or a garage door in the Doors and windows colour
/// family, filled while it is open, unlocked or moving. The tile is the button, as the web's was; VoiceOver reads
/// "Front Door, Locked" with a hint for what a tap does. Owner, 2026-10-16: show the doors as tiles, not rows.
struct SecurityDoorTile: View {
    var tile: SecurityConfig.Tile
    var caller: any HassServiceCalling
    var canSend: Bool
    @Environment(EntityStore.self) private var store
    /// The lock's tapped state, shown until Home Assistant reports a change (rolled back if the call fails).
    @State private var actions: OptimisticActions?

    var body: some View {
        switch tile.kind {
        case .garageDoor:
            GarageDoorTile(tile: tile, liveState: store.entity(tile.entityId).state?.state, caller: caller, canSend: canSend)
                .accessibilityIdentifier("security.tile.\(tile.entityId)")
        case .lock, .vehicle, .alarm:
            LockTile(tile: tile, state: shownState) { call in
                let actions = actions ?? OptimisticActions(store: store, rules: [tile.entityId: .liveChange], caller: caller)
                self.actions = actions
                // Live change clears it: locks report "locking" and "unlocking" on the way.
                actions.perform(call, showing: [OptimisticIntent(tile.entityId, value: call.service == "lock" ? "locked" : "unlocked")])
            }
        }
    }

    /// The live state with any pending tapped value over it.
    private var shownState: EntityState? {
        let live = store.entity(tile.entityId).state
        guard let live, let pending = actions?.shown(tile.entityId), pending != live.state else { return live }
        return EntityState(entityId: live.entityId, state: pending, attributes: live.attributes, lastChanged: live.lastChanged)
    }
}

// MARK: - Lock

/// A lock tile (the front door, or the car): locks when unlocked, unlocks otherwise, with explicit services. Filled
/// while unlocked or moving, the red error face while jammed.
struct LockTile: View {
    var tile: SecurityConfig.Tile
    var state: EntityState?
    var send: (ServiceCall) -> Void

    var body: some View {
        let value = state?.state
        let unavailable = state?.isUnavailable ?? true
        GlassTile(
            title: tile.title,
            subtitle: unavailable ? "Unavailable" : SecurityConfig.stateText(value),
            symbol: Self.symbol(for: tile.kind, state: value),
            family: .contact,
            isActive: Self.isActive(value),
            isUnavailable: unavailable,
            isError: value == "jammed",
            kind: .command
        ) {
            send(SecurityConfig.lockCall(entityId: tile.entityId, state: value))
        }
        .accessibilityHint(unavailable ? "" : (SecurityConfig.lockService(for: value) == "lock" ? "Locks" : "Unlocks"))
        .accessibilityIdentifier("security.tile.\(tile.entityId)")
    }

    /// Whether the tile draws filled: anything but locked (unlocked, open, locking, unlocking, jammed).
    static func isActive(_ state: String?) -> Bool {
        guard let state, !EntityState.isUnavailable(state) else { return false }
        return state != "locked"
    }

    /// The tile's glyph: a padlock that opens with the lock, or the car.
    static func symbol(for kind: SecurityConfig.TileKind, state: String?) -> String {
        if kind == .vehicle { return "car" }
        return state == "locked" || EntityState.isUnavailable(state) ? "lock" : "lock.open"
    }
}
