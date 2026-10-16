import HassCore
import HassDesign
import SwiftUI

// MARK: - Row dispatcher

/// One row of the Security page's Doors (and Mach-E) list (direction G mockup n3): a lock or a garage door, with its
/// state on a capsule. The whole row is the button, as the tile was; VoiceOver reads "Front Door, Locked" with a hint
/// for what a tap does.
struct SecurityDoorRow: View {
    var tile: SecurityConfig.Tile
    var caller: any HassServiceCalling
    var canSend: Bool
    @Environment(EntityStore.self) private var store
    /// The lock's tapped state, shown until Home Assistant reports a change (rolled back if the call fails).
    @State private var actions: OptimisticActions?

    var body: some View {
        switch tile.kind {
        case .garageDoor:
            GarageDoorRow(tile: tile, liveState: store.entity(tile.entityId).state?.state, caller: caller, canSend: canSend)
        case .lock, .vehicle, .alarm:
            LockRow(tile: tile, state: shownState) { call in
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

/// A lock row (front door, or the car): locks when unlocked, unlocks otherwise, with explicit services.
struct LockRow: View {
    var tile: SecurityConfig.Tile
    var state: EntityState?
    var send: (ServiceCall) -> Void

    var body: some View {
        let value = state?.state
        let unavailable = state?.isUnavailable ?? true
        let style = DoorCapsuleStyle.lock(value)
        let text = unavailable ? "Unavailable" : SecurityConfig.stateText(value)
        Button {
            send(SecurityConfig.lockCall(entityId: tile.entityId, state: value))
        } label: {
            ModuleRow(tile.title, symbol: tile.kind == .vehicle ? "car" : "lock", glyph: style.glyph,
                      glyphOpacity: unavailable ? 0.5 : 1) {
                DoorStateCapsule(text: text, symbol: Self.capsuleSymbol(value), style: style)
            }
        }
        .buttonStyle(ModuleRowButtonStyle())
        .disabled(unavailable)
        .accessibilityLabel(tile.title)
        .accessibilityValue(text)
        .accessibilityHint(unavailable ? "" : (SecurityConfig.lockService(for: value) == "lock" ? "Locks" : "Unlocks"))
        .accessibilityIdentifier("security.tile.\(tile.entityId)")
    }

    /// The capsule's glyph for a lock state.
    static func capsuleSymbol(_ state: String?) -> String {
        switch state {
        case "locked": "lock.fill"
        case "unlocked", "open": "lock.open.fill"
        case "jammed": "exclamationmark.triangle.fill"
        default: "lock.rotation"
        }
    }
}

// MARK: - Garage door

/// A garage door row driven by ``GarageDoorController`` (web `GarageDoorTile.tsx`). The capsule carries the command's
/// feedback (direction G: "Garage doors show Sending, Opening, Closing and Error states on their buttons"): an arc
/// spinner and "Sending Open…", then the door's own Opening or Closing, or a red Error.
struct GarageDoorRow: View {
    var tile: SecurityConfig.Tile
    var liveState: String?
    var canSend: Bool
    @State private var controller: GarageDoorController

    init(tile: SecurityConfig.Tile, liveState: String?, caller: any HassServiceCalling, canSend: Bool) {
        self.tile = tile
        self.liveState = liveState
        self.canSend = canSend
        _controller = State(initialValue: GarageDoorController(
            entityId: tile.entityId, liveState: liveState, caller: caller, scheduler: TaskRevertScheduler()
        ))
    }

    var body: some View {
        let unavailable = !controller.isAvailable
        let style = DoorCapsuleStyle.garage(controller)
        let text = GarageDoorTile.subtitle(for: controller)
        Button {
            controller.send()
        } label: {
            ModuleRow(tile.title, symbol: Self.symbol(for: controller), glyph: style.glyph, glyphOpacity: unavailable ? 0.5 : 1) {
                DoorStateCapsule(text: text, symbol: style == .error ? "exclamationmark.triangle.fill" : Self.symbol(for: controller),
                                 style: style)
            }
        }
        .buttonStyle(ModuleRowButtonStyle())
        .disabled(unavailable)
        .accessibilityLabel(tile.title)
        .accessibilityValue(text)
        .accessibilityHint(Self.hint(for: controller))
        .accessibilityIdentifier("security.tile.\(tile.entityId)")
        .garageDoorFeedback(controller, title: tile.title, liveState: liveState, canSend: canSend)
    }

    /// The door's glyph: closed, or open while open or moving.
    static func symbol(for controller: GarageDoorController) -> String {
        SymbolMap.symbol(for: controller.displayState == "closed" || !controller.isAvailable ? "mdi:garage" : "mdi:garage-open")
    }

    /// What a tap does, from the live state.
    static func hint(for controller: GarageDoorController) -> String {
        guard controller.isAvailable else { return "" }
        return GarageDoorController.command(for: controller.liveState)?.opens == true ? "Opens the door" : "Closes the door"
    }
}

// MARK: - State capsule

/// How a door's state capsule is drawn.
enum DoorCapsuleStyle: Equatable {
    /// Locked or closed: neutral.
    case secure
    /// Unlocked or open: warning orange, since the house is open.
    case open
    /// Locking, unlocking, opening or closing: the tint.
    case moving
    /// A garage command is on its way: an arc spinner.
    case sending
    /// The command failed, or the lock jammed: red.
    case error
    /// Home Assistant has no state.
    case unavailable

    /// The style for a lock state.
    static func lock(_ state: String?) -> Self {
        guard !EntityState.isUnavailable(state) else { return .unavailable }
        switch state {
        case "locked": return .secure
        case "unlocked", "open": return .open
        case "jammed": return .error
        default: return .moving
        }
    }

    /// The style for a garage door's controller: its feedback phase first, then the shown state.
    @MainActor
    static func garage(_ controller: GarageDoorController) -> Self {
        switch controller.phase {
        case .sending: return .sending
        case .error: return .error
        case .idle, .pending: break
        }
        guard controller.isAvailable else { return .unavailable }
        switch controller.displayState {
        case "closed": return .secure
        case "open": return .open
        default: return .moving
        }
    }

    /// The row's leading glyph colour: the contact family, brighter while open or moving, red on an error.
    var glyph: Color {
        switch self {
        case .secure, .sending: ColorFamily.contact.offGlyph
        case .open, .moving: ColorFamily.contact.glyph
        case .error: Color(rgb: HassTokens.Palette.red)
        case .unavailable: ColorFamily.neutral.glyph
        }
    }

    /// Text and glyph colour on the capsule (each at 4.5:1 or better on its fill over a module).
    var ink: Color {
        switch self {
        case .secure, .moving: .white
        case .open: Color(rgb: HassTokens.Palette.orange)
        case .error: Color(rgb: HassTokens.Palette.red)
        case .sending, .unavailable: HassTokens.Surface.secondaryOnWash
        }
    }
}

/// A door's state on a capsule at the end of its row: glyph and state, or an arc spinner while a command is sent.
struct DoorStateCapsule: View {
    var text: String
    var symbol: String
    var style: DoorCapsuleStyle

    var body: some View {
        HStack(spacing: 5) {
            if style == .sending {
                ArcSpinner(.inline, label: text)
            } else {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(style.ink)
        .padding(.leading, 10)
        .padding(.trailing, HassTokens.Spacing.m)
        .padding(.vertical, 7)
        .frame(minHeight: 32)
        .background { fill }
        // The row is the control and speaks the state itself.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fill: some View {
        switch style {
        case .secure, .sending, .unavailable: Capsule().fill(.fill.tertiary)
        case .open: Capsule().fill(Color(rgb: HassTokens.Palette.orange).opacity(0.2))
        case .moving: Capsule().fill(HassTokens.Ink.actionFill.opacity(0.55))
        case .error: Capsule().fill(.black.opacity(0.45))
        }
    }
}
