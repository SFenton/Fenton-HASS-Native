import HassCore
import HassDesign
import SwiftUI

// MARK: - Service seam

/// A service caller that stands in for the app's connection (the debug gallery's recorder, hosted tests).
private struct RoomServiceCallerKey: EnvironmentKey {
    // `nil` is the only value ever stored here; injected callers live in the environment, not this static.
    nonisolated(unsafe) static let defaultValue: (any HassServiceCalling)? = nil
}

/// Whether the signed-in user is a Home Assistant administrator (bedroom alarm editing).
private struct HouseholdViewerIsAdminKey: EnvironmentKey {
    static let defaultValue = false
}

/// The signed-in household member, for personalized card titles ("Your Side").
private struct HouseholdViewerKey: EnvironmentKey {
    static let defaultValue: HouseholdResident? = nil
}

extension EnvironmentValues {
    /// Overrides where room pages send service calls; `nil` uses the app's ``HassConnection``.
    var roomServiceCaller: (any HassServiceCalling)? {
        get { self[RoomServiceCallerKey.self] }
        set { self[RoomServiceCallerKey.self] = newValue }
    }

    /// Whether the user may edit admin-only settings such as bedroom alarms; false until known.
    var householdViewerIsAdmin: Bool {
        get { self[HouseholdViewerIsAdminKey.self] }
        set { self[HouseholdViewerIsAdminKey.self] = newValue }
    }

    /// The household member using the app, when known.
    var householdViewer: HouseholdResident? {
        get { self[HouseholdViewerKey.self] }
        set { self[HouseholdViewerKey.self] = newValue }
    }
}

// MARK: - Colors

extension RoomTone {
    /// The tint for an active tile of this tone (web `GlassTile` tone colors).
    var color: Color {
        switch self {
        case .light: HassTokens.Tint.light
        case .air: Color(red: 0.26, green: 0.63, blue: 0.28)
        case .climate: HassTokens.Tint.climate
        case .presence: HassTokens.Tint.presence
        case .contact: HassTokens.Tint.contact
        case .vacuum: Color(red: 0.40, green: 0.33, blue: 0.80)
        case .media: RemoteStyle.media
        case .power: HassTokens.Tint.presence
        case .warning: Color(red: 0.81, green: 0.45, blue: 0.15)
        case .neutral: Color(red: 0.45, green: 0.47, blue: 0.50)
        }
    }
}

extension RoomTone {
    /// The tone's direction G colour family (`.agents/design/direction-g.md`, Colour families); nil when it has none.
    var family: ColorFamily? {
        switch self {
        case .light: .lights
        case .air: .air
        case .climate: .climate
        case .presence: .occupancy
        case .contact: .contact
        case .vacuum: .cleaning
        case .media: .media
        case .power: .power
        case .warning, .neutral: nil
        }
    }
}

extension RoomColor {
    /// The SwiftUI color, alpha included.
    var color: Color { Color(red: red, green: green, blue: blue).opacity(opacity) }
}

// MARK: - Colour families

/// A room tile's direction G face: the device's colour family and whether the tile draws on
/// (`.agents/design/direction-g.md`, Colour families). Pure, so the mapping is tested apart from the drawing.
///
/// Off tiles stay dark with the glyph in the family colour; on tiles fill with it, and lights use the warm lit tile.
struct RoomTileFace: Equatable {
    var family: ColorFamily
    var isActive: Bool

    /// Light cards that are really power devices (the towel rack's heat wave): bright yellow, not the lit tile.
    static let powerIcons: Set<String> = ["mdi:heat-wave"]

    /// The family a kind of card belongs to. Thermostats and bed sides change family with their action
    /// (``resolve(_:entity:display:)``).
    static func family(_ kind: RoomCardKind, icon: String) -> ColorFamily {
        switch kind {
        case .light, .wakeLight: powerIcons.contains(icon) ? .power : .lights
        case .air, .fan: .air
        case .vent: .vents
        case .humidifier: .water
        case .climate: .neutral
        case .occupancy: .occupancy
        case .contact: .contact
        case .vacuum, .appliance, .laundry: .cleaning
        case .media: .media
        case .power: .power
        case .grill: .cooking
        }
    }

    /// The face for a card in its current state.
    /// - Parameters:
    ///   - card: The room card.
    ///   - entity: The entity the card shows now (``RoomController/displayEntity(_:)``).
    ///   - display: The controller's display for the card; a toggle keeps its on/off reading so VoiceOver's value
    ///     and the face agree.
    ///   - running: The card shows its running alternate (the dishwasher mid-cycle).
    static func resolve(_ card: RoomCard, entity: EntityState?, display: RoomCardDisplay, running: Bool = false) -> RoomTileFace {
        let family = family(card.kind, icon: card.icon)
        if case .toggle = display.semantics { return RoomTileFace(family: family, isActive: !display.isOff) }
        guard !display.isUnavailable else { return RoomTileFace(family: family, isActive: false) }
        let on = running || RoomFormat.isActive(entity) || entity.map { card.activeStates.contains($0.state) } == true
        switch card.kind {
        case .light, .fan, .media, .power, .grill:
            return RoomTileFace(family: family, isActive: !display.isOff)
        case .air:
            // The purifier card reads its fan mode, set whenever it runs; the air quality card is a reading.
            return RoomTileFace(family: family, isActive: entity?.domain != "sensor" && entity?.state != "off")
        case .climate:
            // Heating and cooling fill with the dial's colours (web `climateActionTone`); idle and off stay dark.
            let action = entity.map { $0.attributes["hvac_action"]?.string ?? $0.state } ?? ""
            switch action {
            case "heating": return RoomTileFace(family: .heating, isActive: true)
            case "cooling": return RoomTileFace(family: .cooling, isActive: true)
            default: return RoomTileFace(family: family, isActive: false)
            }
        case .occupancy:
            return RoomTileFace(family: family, isActive: RoomFormat.isOccupied(entity))
        case .vacuum:
            return RoomTileFace(family: family, isActive: on || entity?.state == "cleaning")
        case .wakeLight, .vent, .humidifier, .contact, .appliance, .laundry:
            return RoomTileFace(family: family, isActive: on)
        }
    }
}

// MARK: - Section header

/// A room section's title (web `SectionHeader`, and `RoomSectionHeader` inside room sheets): a heading for
/// VoiceOver's rotor. Direction G draws it 20 Bold on pages and over tile grids in sheets
/// (`.agents/design/direction-g.md`, Type).
struct RoomSectionHeader: View {
    var title: String
    /// Inside a sheet the title sits a little below the run above it.
    var inSheet = false

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, inSheet ? HassTokens.Spacing.s : 0)
            .accessibilityAddTraits(.isHeader)
    }
}
