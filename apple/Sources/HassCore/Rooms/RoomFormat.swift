import Foundation

/// State text and activity rules shared by room cards, chips and sheets, ported from the web helpers.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/entityState.ts`, `airQualityState.ts`,
/// `src/pages/DashboardViewPage.tsx:628-646`.
public enum RoomFormat {
    // MARK: - Entity states

    /// `formatCompactEntityState`: contact sensors read Open/Closed, other binary sensors Active/Clear, lights On/Off,
    /// sensors and text helpers their raw state, everything else title case. A missing entity reads "Unavailable".
    public static func compact(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        let state = entity.state
        if state == "unavailable" { return "Unavailable" }
        if entity.entityId.hasPrefix("binary_sensor.contact") { return state == "on" ? "Open" : "Closed" }
        if entity.domain == "binary_sensor" { return state == "on" ? "Active" : "Clear" }
        if entity.domain == "light" { return state == "on" ? "On" : "Off" }
        if entity.domain == "sensor" || entity.domain == "input_text" { return state }
        return StateText.titleCase(state)
    }

    /// `formatOccupancyEntityState`: Detected / Clear.
    public static func occupancy(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        switch entity.state {
        case "unavailable": return "Unavailable"
        case "unknown": return "Unknown"
        case _ where isOccupied(entity): return "Detected"
        case "off", "inactive", "clear", "not_occupied": return "Clear"
        default: return StateText.titleCase(entity.state)
        }
    }

    /// `formatContactEntityState`: Open / Closed.
    public static func contact(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        switch entity.state {
        case "unavailable": return "Unavailable"
        case "unknown": return "Unknown"
        case _ where isOpen(entity): return "Open"
        case "off", "closed": return "Closed"
        default: return StateText.titleCase(entity.state)
        }
    }

    /// `isOccupancyActive`.
    public static func isOccupied(_ entity: EntityState?) -> Bool {
        ["on", "active", "occupied"].contains(entity?.state ?? "")
    }

    /// `isContactOpen`.
    public static func isOpen(_ entity: EntityState?) -> Bool {
        ["on", "open"].contains(entity?.state ?? "")
    }

    /// `isActiveState`: alarm panels are active unless disarmed; others when on, open, playing, recording, home,
    /// heat or cool. (Narrower than `EntityState.isActive`, which the Home rail uses.)
    public static func isActive(_ entity: EntityState?) -> Bool {
        guard let entity else { return false }
        if entity.domain == "alarm_control_panel" { return entity.state != "disarmed" }
        return ["on", "open", "playing", "recording", "home", "heat", "cool"].contains(entity.state)
    }

    /// Missing, `unavailable` or `unknown` (web `isUnavailable` on room cards).
    public static func isUnavailable(_ entity: EntityState?) -> Bool {
        EntityState.isUnavailable(entity?.state)
    }

    /// `formatRoomSourceSubtitleEntity`: the compact state plus its unit, e.g. `45%`.
    public static func withUnit(_ entity: EntityState?) -> String {
        let value = compact(entity)
        guard let unit = entity?.attributes["unit_of_measurement"]?.string, !unit.isEmpty,
              value != "Unavailable", value != "Unknown", !value.hasSuffix(unit) else { return value }
        return value + unit
    }

    // MARK: - Air quality

    /// The AQI sensor next to a purifier's PM2.5 sensor (web `derivedAirPurifierEntityIds`).
    public static func aqiEntityId(forPM25 pm25EntityId: String) -> String {
        var base = pm25EntityId
        if base.hasPrefix("sensor.") { base.removeFirst("sensor.".count) }
        if base.hasSuffix("_pm2_5") { base.removeLast("_pm2_5".count) }
        return "sensor.\(base)_air_quality_index"
    }

    /// `formatAirMetricState`: value and unit (`12 µg/m³`), or a unitless value without a trailing `.0`.
    public static func airMetric(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        let raw = entity.state.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || EntityState.isUnavailable(raw) { return compact(entity) }
        let unit = entity.attributes["unit_of_measurement"]?.string ?? ""
        let value = unit.isEmpty && raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
        return !unit.isEmpty && !value.contains(unit) ? "\(value) \(unit)" : value
    }

    /// `formatAirQualitySummary`: "AQI • PM2.5".
    public static func airSummary(aqi: EntityState?, pm25: EntityState?) -> String {
        "\(airMetric(aqi)) • \(airMetric(pm25))"
    }

    // MARK: - Cards

    /// `formatRoomSourceState`: a configured label, else the compact state.
    public static func cardState(_ card: RoomCard, _ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        return card.stateLabels[entity.state] ?? compact(entity)
    }

    /// The wash a card's state calls for: a configured state color, else an Eight Sleep side's `hvac_action`
    /// (web `roomSourceBackgroundColor`).
    public static func background(_ card: RoomCard, _ entity: EntityState?, presence: EntityState?) -> RoomColor? {
        guard let entity else { return nil }
        if let color = card.stateColors[entity.state] { return color }
        guard card.climateActionTone else { return nil }
        let action = entity.attributes["hvac_action"]?.string ?? entity.state
        switch action {
        case "heating": return RoomColor(136, 64, 26, opacity: 0.6)
        case "cooling": return RoomColor(25, 84, 130, opacity: 0.6)
        case "idle": return RoomColor(229, 57, 53, opacity: 0.6)
        default: return entity.state == "off" && presence?.state == "on" ? RoomColor(0, 150, 136, opacity: 0.6) : nil
        }
    }

    // MARK: - Group sheets

    /// `formatTemperature`: state plus unit (`71.2°F`), or the compact state when unavailable.
    public static func temperature(_ entity: EntityState?) -> String {
        guard let entity, !isUnavailable(entity) else { return compact(entity) }
        return entity.state + (entity.attributes["unit_of_measurement"]?.string ?? "")
    }

    /// Whether a contact item is a window (else a door), from its title and entity (web `contactItemKind`).
    public static func isWindow(_ item: RoomGroupItem) -> Bool {
        "\(item.title) \(item.entityId)".lowercased().contains("window")
    }

    /// "Door Open", "All Windows Closed", "2 Doors Open"; mixed rooms join the open kinds with ", " or read
    /// "All Closed" (web `contactGroupOpenSummary`, `roomGroupSummaries.ts`).
    public static func contactSummary(_ group: RoomGroup, state: (String) -> EntityState?) -> String {
        var open = [false: 0, true: 0]
        var total = [false: 0, true: 0]
        for item in group.items {
            let window = isWindow(item)
            total[window, default: 0] += item.contactCount
            if isOpen(state(item.entityId)) { open[window, default: 0] += 1 }
        }
        func summary(window: Bool) -> String {
            let noun = window ? "Window" : "Door"
            let (openCount, totalCount) = (open[window, default: 0], total[window, default: 0])
            if totalCount == 1 { return openCount == 1 ? "\(noun) Open" : "\(noun) Closed" }
            if openCount == 0 { return "All \(noun)s Closed" }
            if openCount == totalCount { return "All \(noun)s Open" }
            return "\(openCount) \(noun)\(openCount == 1 ? "" : "s") Open"
        }
        let kinds = [true, false].filter { total[$0, default: 0] > 0 }
        if kinds.count == 1 { return summary(window: kinds[0]) }
        let parts = kinds.filter { open[$0, default: 0] > 0 }.map { summary(window: $0) }
        return parts.isEmpty ? "All Closed" : parts.joined(separator: ", ")
    }

    /// Kinds whose cards dim while their entity is inactive (web `DefaultRoomSourceCard.inactiveMuted`).
    static let mutedWhenInactive: Set<RoomCardKind> = [.fan, .grill, .light, .media, .power]
}
