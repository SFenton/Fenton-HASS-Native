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

// MARK: - Section header

/// A room section's title (web `SectionHeader`, and `RoomSectionHeader` inside room sheets): a heading for
/// VoiceOver's rotor.
struct RoomSectionHeader: View {
    var title: String
    /// Inside a sheet the title is a step smaller and sits a little below the run above it.
    var inSheet = false

    var body: some View {
        Text(title)
            .font(inSheet ? .headline : .title3.weight(.semibold))
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, inSheet ? HassTokens.Spacing.s : 0)
            .accessibilityAddTraits(.isHeader)
    }
}
