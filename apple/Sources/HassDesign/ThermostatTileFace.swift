/// The colour family and fill of a thermostat or bed-side tile: the one rule every tile of a climate device
/// follows (`.agents/design/direction-g.md`, Colour families; `.agents/patterns/entity-tile.md`).
///
/// Heating and cooling fill the tile with their family. A thermostat that is idle or off keeps a family on its
/// off face (a dark tile, the glyph in the family colour mixed toward grey), so it never falls back to grey
/// (owner, 2026-10-15): the Heating glyph when the device leans toward heat, the Cooling glyph otherwise.
///
/// Pure, so the mapping is tested apart from the drawing.
public struct ThermostatTileFace: Equatable, Sendable {
    /// ``ColorFamily/heating`` or ``ColorFamily/cooling`` (``ColorFamily/neutral`` for an unavailable bed side).
    public var family: ColorFamily
    /// Whether the tile draws filled (heating or cooling now).
    public var isActive: Bool

    /// Creates a face.
    public init(family: ColorFamily, isActive: Bool) {
        self.family = family
        self.isActive = isActive
    }

    /// The face for a thermostat from its action and HVAC mode.
    /// - Parameters:
    ///   - action: `hvac_action` (falling back to the entity state): `heating`, `cooling`, `idle`, `off`…
    ///   - mode: The HVAC mode, which is the entity's state (`heat`, `cool`, `heat_cool`, `off`…).
    public static func thermostat(action: String, mode: String?) -> Self {
        switch action {
        case "heating": Self(family: .heating, isActive: true)
        case "cooling": Self(family: .cooling, isActive: true)
        default: Self(family: mode == "heat" ? .heating : .cooling, isActive: false)
        }
    }

    /// The face for a bed side from its action (`BedLevel.action`) and displayed level.
    /// - Parameters:
    ///   - action: `heating`, `cooling`, `idle` or `off`.
    ///   - level: The side's target level; below zero the off glyph is Cooling, otherwise Heating.
    ///   - isAvailable: The side answers. An unavailable side stays on the grey ``ColorFamily/neutral`` face.
    public static func bedSide(action: String, level: Double?, isAvailable: Bool = true) -> Self {
        guard isAvailable else { return Self(family: .neutral, isActive: false) }
        switch action {
        case "heating": return Self(family: .heating, isActive: true)
        case "cooling": return Self(family: .cooling, isActive: true)
        default: return Self(family: (level ?? 0) < 0 ? .cooling : .heating, isActive: false)
        }
    }
}
