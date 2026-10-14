import SwiftUI

/// A kind of device and the one colour it uses everywhere: tile glyphs, filled tiles and status chips
/// (`.agents/design/direction-g.md`, Colour families; owner, 2026-10-14: "codify some colors for device families,
/// occupancy, contact sensors, vents, etc so we have distinct tile colors throughout the app").
///
/// Off tiles stay dark with the glyph in ``glyph``, mixed toward grey. On tiles fill with ``fill`` and draw their
/// text in ``ink``. Lights have no fill: they use the warm lit tile. Red is never a family; alerts draw a red glyph
/// and state on whatever tile they belong to.
public enum ColorFamily: String, CaseIterable, Sendable {
    case lights
    /// Thermostats and bed sides while heating (the thermostat dial's heat, darkened for white text).
    case heating
    /// Thermostats and bed sides while cooling (the dial's cool, darkened for white text).
    case cooling
    case vents
    /// Fans, purifiers, bath fans and air quality (web air teal).
    case air
    /// Humidifiers and sprinklers.
    case water
    /// Presence and motion sensors (web presence green).
    case occupancy
    /// Contact sensors and the garage (the web's soft contact green).
    case contact
    /// TVs, remotes, consoles, PCs and speakers (web media pink).
    case media
    /// Vacuums, dishwasher and laundry.
    case cleaning
    /// Plugs, the towel rack and chargers: bright yellow with dark text.
    case power
    /// Grill and oven.
    case cooking
    /// Security by alarm mode, as on the web.
    case securityHome, securityAway, securityNight, securityDisarmed, securityTriggered
    /// Anything without a family: grey glyph, no fill.
    case neutral

    /// The family's sRGB values as `0xRRGGBB`, kept raw so tests can check contrast.
    public struct Spec: Sendable, Equatable {
        /// Glyph colour on dark tiles, chips and rows.
        public let glyph: UInt32
        /// On-tile fill, or nil for families that are never filled (lights use the lit tile; neutral).
        public let fill: UInt32?
        /// Whether text on ``fill`` is dark (power) rather than white.
        public let darkInk: Bool
    }

    /// The raw values (direction-g.md table).
    public var spec: Spec {
        switch self {
        case .lights: Spec(glyph: 0xFF9630, fill: nil, darkInk: true)
        case .heating: Spec(glyph: 0xFF7A2F, fill: 0xA8440A, darkInk: false)
        case .cooling: Spec(glyph: 0x3FC6D2, fill: 0x1B6F78, darkInk: false)
        case .vents: Spec(glyph: 0x8FA8FF, fill: 0x3B58B8, darkInk: false)
        case .air: Spec(glyph: 0x2FD3C1, fill: 0x006E62, darkInk: false)
        case .water: Spec(glyph: 0x4CC9F0, fill: 0x076C91, darkInk: false)
        case .occupancy: Spec(glyph: 0x5BD16A, fill: 0x2A732E, darkInk: false)
        case .contact: Spec(glyph: 0x7ED787, fill: 0x3B523E, darkInk: false)
        case .media: Spec(glyph: 0xFF7AA8, fill: 0xA03A61, darkInk: false)
        case .cleaning: Spec(glyph: 0xC88CFA, fill: 0x7A3FB0, darkInk: false)
        case .power: Spec(glyph: 0xFFD60A, fill: 0xFFD60A, darkInk: true)
        case .cooking: Spec(glyph: 0xFF8A4C, fill: 0xA8420E, darkInk: false)
        case .securityHome: Spec(glyph: 0x64B0FF, fill: 0x1565C0, darkInk: false)
        case .securityAway: Spec(glyph: 0xFF6961, fill: 0xC62828, darkInk: false)
        case .securityNight: Spec(glyph: 0xD08CF0, fill: 0x7B1FA2, darkInk: false)
        case .securityDisarmed: Spec(glyph: 0x5BD16A, fill: 0x2A732E, darkInk: false)
        case .securityTriggered: Spec(glyph: 0xFF6961, fill: 0xD70015, darkInk: false)
        case .neutral: Spec(glyph: 0x8E8E93, fill: nil, darkInk: false)
        }
    }

    /// Glyph colour on dark tiles, chips and rows.
    public var glyph: Color { Color(rgb: spec.glyph) }

    /// Glyph colour on an off tile: the family colour mixed 72% with system grey, so the kind of device stays
    /// visible without reading as on.
    public var offGlyph: Color { Color(rgb: Self.mix(spec.glyph, 0x8E8E93, 0.72)) }

    /// The on-tile fill, or nil when the family is never filled.
    public var fill: Color? { spec.fill.map { Color(rgb: $0) } }

    /// Title and glyph colour on ``fill``.
    public var ink: Color { spec.darkInk ? Color(rgb: 0x1C1C1E) : .white }

    /// Supporting text on ``fill``: white at 92% (4.5:1 or better on every fill), or a dark olive on power.
    public var secondaryInk: Color { spec.darkInk ? Color(rgb: 0x282000).opacity(0.82) : .white.opacity(0.92) }

    /// Mixes two `0xRRGGBB` colours: `amount` of `a`, the rest `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let ca = Double((a >> shift) & 0xFF), cb = Double((b >> shift) & 0xFF)
            return UInt32((ca * amount + cb * (1 - amount)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

extension Color {
    /// A colour from `0xRRGGBB` sRGB.
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
