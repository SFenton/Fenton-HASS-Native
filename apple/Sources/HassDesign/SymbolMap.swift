/// Maps the web dashboard's Material Design Icon names to SF Symbols.
///
/// Add a row whenever a ported surface uses a new MDI name; unknown names fall back to a neutral circle.
public enum SymbolMap {
    static let table: [String: String] = [
        "mdi:home": "house",
        "mdi:shield": "shield",
        "mdi:shield-outline": "shield",
        "mdi:thermostat": "thermometer.medium",
        "mdi:thermometer": "thermometer.medium",
        "mdi:clipboard-list": "checklist",
        "mdi:cog": "gearshape",
        "mdi:lightbulb-group": "lightbulb.2",
        "mdi:lightbulb": "lightbulb",
        "mdi:motion-sensor": "figure.walk.motion",
        "mdi:door": "door.left.hand.closed",
        "mdi:bed": "bed.double",
        "mdi:guitar-electric": "guitars",
        "mdi:projector": "videoprojector",
        "mdi:cctv": "video",
        "mdi:shield-account": "person.badge.shield.checkmark",
        "mdi:tune-vertical": "slider.vertical.3",
        "mdi:account-multiple": "person.2",
        "mdi:airplane": "airplane",
        "mdi:car-estate": "car.side",
    ]

    /// The SF Symbol name for an MDI icon.
    public static func symbol(for mdi: String) -> String {
        table[mdi] ?? "circle"
    }
}
