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

// MARK: - Garage door tile

/// A garage door tile driven by ``GarageDoorController`` (web `GarageDoorTile.tsx`): the garage room cards draw it.
/// The Security page's Doors section shows the same tile (``SecurityDoorTile``). Direction G: the contact family,
/// filled while the door is open or moving, and the red error face after a failed command.
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
        GlassTile(
            title: tile.title,
            subtitle: Self.subtitle(for: controller),
            symbol: Self.symbol(for: controller),
            family: .contact,
            isActive: !unavailable && controller.displayState != "closed",
            isUnavailable: unavailable,
            isError: controller.phase == .error,
            kind: .command
        ) {
            controller.send()
        }
        .accessibilityHint(Self.hint(for: controller))
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

// MARK: - Door feedback

extension View {
    /// Feeds a garage door's live state and connection into its controller, and announces its feedback to VoiceOver
    /// without moving focus (web `announcement`). 
    func garageDoorFeedback(_ controller: GarageDoorController, title: String, liveState: String?, canSend: Bool) -> some View {
        modifier(GarageDoorFeedback(controller: controller, title: title, liveState: liveState, canSend: canSend))
    }
}

private struct GarageDoorFeedback: ViewModifier {
    var controller: GarageDoorController
    var title: String
    var liveState: String?
    var canSend: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                controller.liveDidChange(liveState)
                controller.connectionDidChange(canSend: canSend)
            }
            .onChange(of: liveState) { _, state in controller.liveDidChange(state) }
            .onChange(of: canSend) { _, value in controller.connectionDidChange(canSend: value) }
            .onChange(of: controller.phase) { _, phase in
                if phase != .idle {
                    AccessibilityNotification.Announcement("\(title), \(GarageDoorTile.subtitle(for: controller))").post()
                }
            }
    }
}
