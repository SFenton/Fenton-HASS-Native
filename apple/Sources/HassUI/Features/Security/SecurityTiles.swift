import HassCore
import HassDesign
import SwiftUI

// MARK: - Colors

extension SecurityConfig.Tone {
    /// Tile tint (web `GlassTile` tone colors: `contact` green, `security` blue, `danger` red).
    var color: Color {
        switch self {
        case .secure: Color(red: 67 / 255, green: 160 / 255, blue: 71 / 255)
        case .active: Color(red: 30 / 255, green: 136 / 255, blue: 229 / 255)
        case .danger: Color(red: 229 / 255, green: 57 / 255, blue: 53 / 255)
        case .neutral: HassTokens.Tint.neutral
        }
    }
}

extension SecurityConfig {
    /// An alarm state's color (`securityStateColor`).
    static func alarmTint(for state: String?) -> Color {
        let rgb = alarmColor(for: state)
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

// MARK: - Tiles

/// One Security tile, by kind.
struct SecurityTile: View {
    var tile: SecurityConfig.Tile
    var caller: any HassServiceCalling
    var canSend: Bool
    var openSystem: () -> Void
    @Environment(EntityStore.self) private var store
    @State private var failure: String?

    var body: some View {
        Group {
            switch tile.kind {
            case .alarm:
                AlarmTile(tile: tile, state: store.entity(tile.entityId).state, action: openSystem)
            case .lock, .vehicle:
                LockTile(tile: tile, state: store.entity(tile.entityId).state) { call in
                    Task {
                        do {
                            try await caller.call(call)
                        } catch {
                            failure = "Home Assistant didn't update \(tile.title). Check the connection and try again."
                        }
                    }
                }
            case .garageDoor:
                GarageDoorTile(tile: tile, liveState: store.entity(tile.entityId).state?.state, caller: caller, canSend: canSend)
            }
        }
        .alert("Couldn't Update \(tile.title)", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }
}

/// The Security System tile: the panel's mode; opens the mode sheet.
struct AlarmTile: View {
    var tile: SecurityConfig.Tile
    var state: EntityState?
    var action: () -> Void

    var body: some View {
        let redacting = ScreenshotPrivacy.isRedacting
        let unavailable = state?.isUnavailable ?? true
        GlassTile(
            title: tile.title,
            subtitle: redacting ? "Hidden" : (unavailable ? "Unavailable" : SecurityConfig.stateText(state?.state)),
            symbol: SymbolMap.symbol(for: redacting ? tile.icon : SecurityConfig.alarmIcon(for: state?.state)),
            tint: redacting ? SecurityConfig.Tone.active.color : SecurityConfig.tone(for: .alarm, state: state?.state).color,
            isActive: !unavailable,
            isUnavailable: unavailable,
            kind: .navigate,
            action: action
        )
        .accessibilityHint("Opens security system modes")
    }
}

/// A lock tile (front door, or the car): locks when unlocked, unlocks otherwise, with explicit services.
struct LockTile: View {
    var tile: SecurityConfig.Tile
    var state: EntityState?
    var send: (ServiceCall) -> Void

    var body: some View {
        let value = state?.state
        let unavailable = state?.isUnavailable ?? true
        let locks = SecurityConfig.lockService(for: value) == "lock"
        let open = value == "unlocked" || value == "open"
        GlassTile(
            title: tile.title,
            subtitle: unavailable ? "Unavailable" : SecurityConfig.stateText(value),
            symbol: tile.kind == .vehicle ? SymbolMap.symbol(for: tile.icon) : (open ? "lock.open" : "lock"),
            tint: SecurityConfig.tone(for: tile.kind, state: value).color,
            // The web mutes the car tile unless it is unlocked or open (`isActiveState`).
            isActive: tile.kind == .vehicle ? open : !unavailable,
            isUnavailable: unavailable,
            kind: .command
        ) {
            send(SecurityConfig.lockCall(entityId: tile.entityId, state: value))
        }
        .accessibilityHint(unavailable ? "" : (locks ? "Locks" : "Unlocks"))
    }
}

/// A garage door tile driven by ``GarageDoorController`` (web `GarageDoorTile.tsx`).
struct GarageDoorTile: View {
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
        let text = Self.subtitle(for: controller)
        GlassTile(
            title: tile.title,
            subtitle: text,
            symbol: SymbolMap.symbol(for: controller.displayState == "closed" || unavailable ? "mdi:garage" : "mdi:garage-open"),
            tint: Self.tone(for: controller).color,
            isActive: !unavailable,
            isUnavailable: unavailable,
            kind: .command
        ) {
            controller.send()
        }
        .accessibilityHint(unavailable ? "" : (GarageDoorController.command(for: controller.liveState)?.opens == true ? "Opens the door" : "Closes the door"))
        .onAppear {
            controller.liveDidChange(liveState)
            controller.connectionDidChange(canSend: canSend)
        }
        .onChange(of: liveState) { _, state in controller.liveDidChange(state) }
        .onChange(of: canSend) { _, value in controller.connectionDidChange(canSend: value) }
        .onChange(of: controller.phase) { _, phase in
            // VoiceOver hears the feedback without moving focus (web `announcement`).
            if phase != .idle { AccessibilityNotification.Announcement("\(tile.title), \(Self.subtitle(for: controller))").post() }
        }
    }

    /// "Sending Open…" / "Sending Close…" while sending, "Error" after a failure, else the shown state.
    static func subtitle(for controller: GarageDoorController) -> String {
        switch controller.phase {
        case .sending: controller.opens == true ? "Sending Open…" : "Sending Close…"
        case .error: "Error"
        case .idle, .pending:
            controller.liveState == "unavailable" ? "Unavailable" : SecurityConfig.stateText(controller.displayState)
        }
    }

    /// Red after a failure, else the shown state's tone.
    static func tone(for controller: GarageDoorController) -> SecurityConfig.Tone {
        controller.phase == .error ? .danger : SecurityConfig.tone(for: .garageDoor, state: controller.displayState)
    }
}
