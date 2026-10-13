import Foundation

/// A highlight tile of the weather sheet (everything under "Highlights" except the chart tiles).
public struct WeatherHighlight: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case aqi, feels, uv, wind, sun, visibility, pressure
    }

    /// Wind tile details.
    public struct Wind: Equatable, Sendable {
        public var bearingDegrees: Double?
        public var destinationDegrees: Double?
        public var directionLabel: String
        public var directionValue: String
        public var gustIsForecast: Bool
        public var gustLabel: String
        public var gustValue: String
        public var showVector: Bool
        public var speedLabel: String
        public var speedValue: String
    }

    public var kind: Kind
    public var id: String { kind.rawValue }
    /// Spoken name for the whole tile, when it differs from "title value".
    public var accessibilityLabel: String
    public var available: Bool
    /// Web MDI icon name.
    public var icon: String
    /// 0...100 marker position on the tile's gauge.
    public var percent: Double?
    public var rotation: Double?
    /// Category text, e.g. `Moderate`.
    public var status: String?
    public var title: String
    public var value: String
    public var wind: Wind?
    /// A mild tone key for the AQI tile (the level name), `unavailable` otherwise.
    public var tone: String?
}

/// Builds the highlight tiles from current conditions, today's forecast and the sun.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/WeatherSummary.tsx:511` (`highlightTiles`) and
/// `WeatherAqiTile` (`:1006`).
public enum WeatherHighlights {
    /// Feels Like, UV Index, Wind, Sunrise/Sunset, Visibility and Pressure, in web order.
    public static func tiles(current: WeatherCurrent, today: WeatherForecast?, sun: WeatherSunInput?, now: Date = Date(), timeZone: TimeZone = .current) -> [WeatherHighlight] {
        let unavailable = WeatherCopy.text("unavailable")
        let wind = WeatherFormat.windMeasure(current.windSpeed, unit: current.windSpeedUnit)
        let currentGust = current.windGustSpeed
        let dailyGust = today?.windGustSpeed
        let gustIsForecast = currentGust == nil && dailyGust != nil
        let gust = WeatherFormat.windMeasure(currentGust ?? dailyGust, unit: current.windSpeedUnit)
        let bearing = WeatherPresentation.windBearing(current.windBearing)
        let calm = wind?.numeric == 0
        let gustLabel = WeatherCopy.text(gustIsForecast ? "details.wind.todaysGust" : "details.wind.gusts")
        let directionLabel = WeatherCopy.text(calm || bearing == nil ? "details.wind.direction" : "details.wind.from")
        let directionValue: String
        let directionSpoken: String
        if calm {
            directionValue = WeatherCopy.text("details.wind.calm")
            directionSpoken = directionValue
        } else if let bearing {
            directionValue = bearing.cardinal + (bearing.displayDegrees.map { " · \($0)°" } ?? "")
            directionSpoken = bearing.displayDegrees.map {
                WeatherCopy.text("details.wind.bearingDegrees", ["degrees": String($0), "direction": bearing.spoken])
            } ?? bearing.spoken
        } else {
            directionValue = unavailable
            directionSpoken = unavailable
        }
        let windAria = WeatherCopy.text("details.wind.ariaLabel", [
            "direction": directionSpoken, "directionLabel": directionLabel, "gust": gust?.value ?? unavailable,
            "gustLabel": gustLabel, "speed": wind?.value ?? unavailable,
        ])

        let pressure = WeatherPresentation.pressure(current.pressure, unit: current.pressureUnit)
        let uv = WeatherPresentation.uv(today?.uvIndex)
        let feels = WeatherPresentation.feelsLike(actual: current.temperature, apparent: current.apparentTemperature, unit: current.temperatureUnit)
        let visibility = WeatherPresentation.visibility(current.visibility, unit: current.visibilityUnit)
        let sunReading = sun.flatMap { WeatherPresentation.sun(state: $0.state, nextRising: $0.nextRising, nextSetting: $0.nextSetting, now: now) }
        let sunValue = sunReading.map { WeatherDates.clock($0.primaryTime, in: timeZone) }

        func accessible(_ title: String, _ value: String, available: Bool, status: String? = nil) -> String {
            let text = available ? [value, status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") : unavailable
            return WeatherCopy.text("details.ariaLabel", ["title": title, "value": text])
        }

        var tiles: [WeatherHighlight] = []
        tiles.append(WeatherHighlight(
            kind: .feels, accessibilityLabel: accessible("Feels Like", feels == nil ? "--" : WeatherFormat.temperature(current.apparentTemperature, unit: current.temperatureUnit), available: feels != nil),
            available: feels != nil, icon: "mdi:thermometer-lines", percent: feels?.markerPercent, rotation: nil, status: nil,
            title: "Feels Like", value: feels == nil ? "--" : WeatherFormat.temperature(current.apparentTemperature, unit: current.temperatureUnit),
            wind: nil, tone: feels?.relation.rawValue
        ))
        let uvStatus = uv.map { WeatherCopy.text($0.level.categoryKey) }
        let uvValue = uv.map { WeatherFormat.number($0.value, digits: 1) ?? unavailable } ?? "--"
        tiles.append(WeatherHighlight(
            kind: .uv, accessibilityLabel: accessible("UV Index", uvValue, available: uv != nil, status: uvStatus),
            available: uv != nil, icon: "mdi:weather-sunny-alert", percent: uv?.markerPercent, rotation: nil, status: uvStatus,
            title: "UV Index", value: uvValue, wind: nil, tone: uv?.level.rawValue
        ))
        tiles.append(WeatherHighlight(
            kind: .wind, accessibilityLabel: windAria, available: wind != nil || gust != nil || bearing != nil, icon: "mdi:weather-windy",
            percent: nil, rotation: nil, status: nil, title: "Wind", value: wind?.value ?? "--",
            wind: .init(
                bearingDegrees: calm ? nil : bearing?.sourceDegrees, destinationDegrees: calm ? nil : bearing?.destinationDegrees,
                directionLabel: directionLabel, directionValue: directionValue, gustIsForecast: gustIsForecast,
                gustLabel: gustLabel, gustValue: gust?.value ?? unavailable, showVector: bearing != nil && !calm,
                speedLabel: WeatherCopy.text("details.wind.speed"), speedValue: wind?.value ?? unavailable
            ),
            tone: nil
        ))
        if sun != nil {
            let title = sunReading.map { WeatherCopy.text($0.titleKey) } ?? WeatherCopy.text("details.sun.sunset")
            tiles.append(WeatherHighlight(
                kind: .sun, accessibilityLabel: accessible(title, sunValue ?? "--", available: sunReading != nil && sunValue != nil),
                available: sunReading != nil && sunValue != nil, icon: "mdi:weather-sunny", percent: sunReading?.markerPercent,
                rotation: nil, status: nil, title: title, value: sunValue ?? "--", wind: nil, tone: nil
            ))
        }
        let visibilityValue = visibility == nil ? "--" : WeatherFormat.measure(current.visibility, unit: current.visibilityUnit, digits: 1) ?? "--"
        tiles.append(WeatherHighlight(
            kind: .visibility, accessibilityLabel: accessible("Visibility", visibilityValue, available: visibility != nil),
            available: visibility != nil, icon: "mdi:eye", percent: visibility?.markerPercent, rotation: nil, status: nil,
            title: "Visibility", value: visibilityValue, wind: nil, tone: visibility?.band.rawValue
        ))
        let pressureValue = pressure == nil ? "--" : WeatherFormat.measure(current.pressure, unit: current.pressureUnit, digits: 2) ?? "--"
        tiles.append(WeatherHighlight(
            kind: .pressure, accessibilityLabel: accessible("Pressure", pressureValue, available: pressure != nil),
            available: pressure != nil, icon: "mdi:gauge", percent: pressure?.markerPercent,
            rotation: pressure.map { ($0.markerPercent - 50) * 1.35 }, status: nil, title: "Pressure", value: pressureValue,
            wind: nil, tone: pressure?.band.rawValue
        ))
        return tiles
    }

    /// The Air Quality tile from the `sensor.pirate_weather_air_quality_index` state.
    public static func airQuality(state: String?) -> WeatherHighlight {
        let reading = WeatherPresentation.classifyUsAqi(state: state)
        let unavailable = WeatherCopy.text("unavailable")
        let category = reading.map { WeatherCopy.text($0.level.categoryKey) } ?? unavailable
        let value = reading.map { String($0.value) } ?? "--"
        let label = reading != nil
            ? WeatherCopy.text("aqi.ariaLabel", ["category": category, "value": value])
            : WeatherCopy.text("aqi.unavailableAriaLabel")
        return WeatherHighlight(
            kind: .aqi, accessibilityLabel: label, available: reading != nil, icon: "mdi:air-filter", percent: reading?.markerPercent,
            rotation: nil, status: category, title: WeatherCopy.text("aqi.title"), value: value, wind: nil, tone: reading?.level.rawValue ?? "unavailable"
        )
    }
}

/// A temperature range drawn as a rail: where the span starts, how long it is and where "now" sits (all 0...100).
public struct WeatherRailRange: Equatable, Sendable {
    public var markerPercent: Double?
    public var rangeSizePercent: Double?
    public var rangeStartPercent: Double?

    public init(markerPercent: Double? = nil, rangeSizePercent: Double? = nil, rangeStartPercent: Double? = nil) {
        self.markerPercent = markerPercent
        self.rangeSizePercent = rangeSizePercent
        self.rangeStartPercent = rangeStartPercent
    }
}

/// Rail geometry for the Today row and the seven-day rows.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/WeatherSummary.tsx:457`.
public enum WeatherRails {
    /// A day's low-to-high span positioned inside the week's overall span; day 0 carries the current-temperature marker.
    public static func week(forecast: WeatherForecast, all forecasts: [WeatherForecast], currentTemperature: Double?, index: Int) -> WeatherRailRange? {
        let ranges = forecasts.compactMap { item -> (low: Double, high: Double)? in
            guard let low = item.templow, let high = item.temperature, high >= low else { return nil }
            return (low, high)
        }
        guard let low = forecast.templow, let high = forecast.temperature, high >= low, !ranges.isEmpty else { return nil }
        let minLow = ranges.map(\.low).min() ?? low
        let maxHigh = ranges.map(\.high).max() ?? high
        let spread = maxHigh - minLow
        let current = index == 0 ? currentTemperature : nil
        if spread == 0 {
            return WeatherRailRange(markerPercent: current.map { $0 < low ? 0 : $0 > high ? 100 : 50 }, rangeSizePercent: 0, rangeStartPercent: 50)
        }
        return WeatherRailRange(
            markerPercent: current.map { WeatherPresentation.clampPercent(($0 - minLow) / spread * 100) },
            rangeSizePercent: WeatherPresentation.clampPercent((high - low) / spread * 100),
            rangeStartPercent: WeatherPresentation.clampPercent((low - minLow) / spread * 100)
        )
    }

    /// Today's rail spans the whole track; the marker is the current temperature between low and high.
    public static func hero(forecast: WeatherForecast, currentTemperature: Double?) -> WeatherRailRange? {
        guard let low = forecast.templow, let high = forecast.temperature, high >= low else { return nil }
        let spread = high - low
        if spread == 0 {
            return WeatherRailRange(markerPercent: currentTemperature.map { $0 < low ? 0 : $0 > high ? 100 : 50 }, rangeSizePercent: 0, rangeStartPercent: 50)
        }
        return WeatherRailRange(
            markerPercent: currentTemperature.map { WeatherPresentation.clampPercent(($0 - low) / spread * 100) },
            rangeSizePercent: 100, rangeStartPercent: 0
        )
    }
}
