import HassCore
import HassDesign
import SwiftUI

/// The "Highlights" grid (web `highlightsPanel`): air quality, precipitation and accumulation, humidity and cloud
/// cover, then feels like, UV, wind, sun, visibility and pressure. Laid out on ``DynamicGridLayout``: wide tiles
/// take two tracks, and at larger text sizes the grid drops to fewer columns instead of clipping.
struct WeatherHighlightsPanel: View {
    var forecasts: WeatherForecastStore
    var current: WeatherCurrent
    var sun: WeatherSunInput?

    @Environment(EntityStore.self) private var entities
    /// Narrowest a tile may be; grows with Dynamic Type so the grid reflows to fewer columns.
    @ScaledMetric(relativeTo: .footnote) private var tileWidth: CGFloat = 150

    var body: some View {
        let hourly = forecasts.hourly.forecasts
        let tiles = WeatherHighlights.tiles(current: current, today: forecasts.daily.forecasts.first, sun: sun)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text("Highlights")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: tileWidth, maxColumns: 4) {
                if let aqiState = entities.entity(WeatherEntities.airQuality).state {
                    WeatherAqiTile(tile: WeatherHighlights.airQuality(state: aqiState.state)).gridSpan(2)
                }
                WeatherChanceTile(forecasts: hourly).gridSpan(2)
                WeatherAccumulationTile(forecasts: hourly, unit: current.precipitationUnit ?? WeatherUnits.defaultPrecipitationUnit).gridSpan(2)
                WeatherMetricTile(forecasts: hourly, metric: .humidity).gridSpan(2)
                WeatherMetricTile(forecasts: hourly, metric: .cloudCover).gridSpan(2)
                ForEach(tiles) { tile in
                    WeatherHighlightTile(tile: tile, sun: sun).gridSpan(tile.kind == .wind ? 2 : 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weather highlights")
        .accessibilityIdentifier("weather.highlights")
    }
}

// MARK: - Air quality

/// The US AQI tile (web `WeatherAqiTile`).
struct WeatherAqiTile: View {
    var tile: WeatherHighlight

    var body: some View {
        WeatherTile(
            title: tile.title, symbol: WeatherSymbols.highlight(.aqi), label: tile.accessibilityLabel,
            identifier: "weather.highlight.aqi", value: nil
        ) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                    Text(tile.value).font(.title.weight(.bold)).monospacedDigit()
                    Text(tile.status ?? "").font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
                }
                WeatherRail(tone: .aqi, range: WeatherRailRange(markerPercent: tile.percent))
            }
        }
    }
}

// MARK: - Charts

/// Hour labels for the first hours: `Now`, then `4 PM`.
private func chartHourLabels(_ points: [PrecipitationPoint]) -> [String] {
    points.enumerated().map { index, point in
        index == 0 ? WeatherCopy.text("precipitation.now") : point.startTime.map { WeatherDates.hour($0) } ?? "--"
    }
}

private func percentText(_ value: Double?) -> String {
    value.map { "\(WeatherFormat.integer($0))%" } ?? WeatherCopy.text("unavailable")
}

private func amountText(_ value: Double?, unit: String) -> String {
    guard let value else { return WeatherCopy.text("unavailable") }
    let normalized = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "in" : unit
    let digits = normalized.lowercased().contains("mm") ? 1 : 2
    return "\(String(format: "%.\(digits)f", value)) \(normalized)"
}

/// Hourly precipitation chance over the next six hours.
struct WeatherChanceTile: View {
    var forecasts: [WeatherForecast]

    var body: some View {
        let points = WeatherPrecipitationTimeline.points(forecasts, limit: 6)
        let peak = WeatherPrecipitationTimeline.peakChance(points)
        let domain = WeatherPrecipitationTimeline.chanceDomain(peak: peak)
        let labels = chartHourLabels(points)
        let series = zip(labels, points).map { "\($0) \(percentText($1.probability))" }.joined(separator: ", ")
        WeatherTile(
            title: WeatherCopy.text("precipitation.title"), symbol: WeatherSymbols.precipitation,
            label: WeatherCopy.text("precipitation.chanceChartAriaLabel", ["chance": percentText(peak), "hours": String(points.count)]),
            identifier: "weather.highlight.precipitation", value: series
        ) {
            if peak != nil {
                WeatherBarChart(
                    values: points.map(\.probability), domain: domain,
                    axisLabels: (percentText(domain), percentText(domain / 2), percentText(0)), hourLabels: labels,
                    tint: Color(red: 0.45, green: 0.78, blue: 1.0)
                )
            } else {
                unavailable
            }
        }
    }

    private var unavailable: some View {
        Text(WeatherCopy.text("unavailable")).font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
    }
}

/// Cumulative precipitation over the next six hours.
struct WeatherAccumulationTile: View {
    var forecasts: [WeatherForecast]
    var unit: String

    var body: some View {
        let points = WeatherPrecipitationTimeline.points(forecasts, limit: 6)
        let total = WeatherPrecipitationTimeline.total(points)
        let axis = WeatherPrecipitationTimeline.amountAxis(total: total, unit: unit)
        let labels = chartHourLabels(points)
        let series = zip(labels, points).map { "\($0) \(amountText($1.cumulative, unit: unit))" }.joined(separator: ", ")
        WeatherTile(
            title: WeatherCopy.text("precipitation.cumulativeHeading"), symbol: WeatherSymbols.precipitation,
            label: WeatherCopy.text("precipitation.cumulativeChartAriaLabel", ["hours": String(points.count), "total": amountText(total, unit: unit)]),
            identifier: "weather.highlight.accumulation", value: series
        ) {
            if total != nil {
                WeatherBarChart(
                    values: points.map(\.cumulative), domain: axis.domain,
                    axisLabels: (axisText(axis.domain, axis), axisText(axis.step, axis), axisText(0, axis)), hourLabels: labels,
                    tint: Color(red: 0.55, green: 0.85, blue: 1.0)
                )
            } else {
                Text(WeatherCopy.text("unavailable")).font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
            }
        }
    }

    private func axisText(_ value: Double, _ axis: PrecipitationAmountAxis) -> String {
        let normalized = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "in" : unit
        let text = WeatherFormat.number(value, digits: axis.maximumFractionDigits) ?? "--"
        return "\(text) \(normalized)"
    }
}

/// Hourly humidity or cloud cover over the next six hours (web `WeatherHourlyMetricTiles`).
struct WeatherMetricTile: View {
    enum Metric {
        case humidity, cloudCover

        var titleKey: String { self == .humidity ? "hourlyMetrics.humidity" : "hourlyMetrics.cloudCover" }
        var symbol: String { self == .humidity ? WeatherSymbols.humidity : WeatherSymbols.cloudCover }
        var identifier: String { self == .humidity ? "weather.highlight.humidity" : "weather.highlight.cloud" }
        var tint: Color { self == .humidity ? Color(red: 0.40, green: 0.85, blue: 0.80) : Color(red: 0.80, green: 0.86, blue: 0.95) }
    }

    var forecasts: [WeatherForecast]
    var metric: Metric

    var body: some View {
        let points = WeatherHourlyMetrics.points(forecasts)
        let values: [Double?] = points.map { metric == .humidity ? $0.humidity : $0.cloudCover }
        let known = values.compactMap { $0 }
        let domain = WeatherPrecipitationTimeline.chanceDomain(peak: known.max())
        let title = WeatherCopy.text(metric.titleKey)
        let labels = points.enumerated().map { index, point in
            index == 0 ? WeatherCopy.text("precipitation.now") : point.time.map { WeatherDates.hour($0) } ?? "--"
        }
        let series = zip(labels, values).map { "\($0) \(percentText($1))" }.joined(separator: ", ")
        WeatherTile(
            title: title, symbol: metric.symbol,
            label: WeatherCopy.text("hourlyMetrics.ariaLabel", [
                "hours": String(points.count), "maximum": percentText(known.max()), "minimum": percentText(known.min()), "title": title,
            ]),
            identifier: metric.identifier, value: series
        ) {
            if known.isEmpty {
                Text(WeatherCopy.text("unavailable")).font(.subheadline).foregroundStyle(HassTokens.Ink.onDarkSecondary)
            } else {
                WeatherBarChart(
                    values: values, domain: domain, axisLabels: (percentText(domain), percentText(domain / 2), percentText(0)),
                    hourLabels: labels, tint: metric.tint
                )
            }
        }
    }
}

// MARK: - Current-condition tiles

/// Feels like, UV, wind, sun, visibility and pressure (web `HighlightTile`).
struct WeatherHighlightTile: View {
    var tile: WeatherHighlight
    var sun: WeatherSunInput?

    var body: some View {
        if tile.kind == .wind, let wind = tile.wind {
            WeatherWindTile(tile: tile, wind: wind)
        } else {
            WeatherTile(
                title: tile.title, symbol: WeatherSymbols.highlight(tile.kind, sun: sunEvent), label: tile.accessibilityLabel,
                identifier: "weather.highlight.\(tile.kind.rawValue)", value: nil
            ) {
                content
            }
        }
    }

    private var sunEvent: WeatherPresentation.SunEvent? {
        sun.flatMap { WeatherPresentation.sun(state: $0.state, nextRising: $0.nextRising, nextSetting: $0.nextSetting)?.primary }
    }

    @ViewBuilder
    private var content: some View {
        if !tile.available {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Text(tile.value).font(.title2.weight(.bold))
                Image(systemName: WeatherSymbols.highlight(tile.kind))
                    .font(.title)
                    .foregroundStyle(HassTokens.Ink.onDark.opacity(0.35))
            }
        } else if tile.kind == .pressure {
            let parts = tile.value.split(separator: " ", maxSplits: 1).map(String.init)
            WeatherPressureGauge(percent: tile.percent ?? 50, value: parts.first ?? tile.value, unit: parts.count > 1 ? parts[1] : nil)
        } else {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.s) {
                    Text(tile.value).font(.title2.weight(.bold)).monospacedDigit()
                    if let status = tile.status {
                        Text(status).font(.footnote).foregroundStyle(HassTokens.Ink.onDarkSecondary)
                    }
                }
                visual
            }
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch tile.kind {
        case .feels: WeatherRail(tone: .feels, range: WeatherRailRange(markerPercent: tile.percent))
        case .uv: WeatherRail(tone: .uv, range: WeatherRailRange(markerPercent: tile.percent))
        case .visibility:
            WeatherRail(tone: .visibility, range: WeatherRailRange(
                markerPercent: (tile.percent ?? 0) > 0 ? tile.percent : nil, rangeSizePercent: tile.percent, rangeStartPercent: 0
            ))
        case .sun: WeatherSunArc(percent: tile.percent)
        default: EmptyView()
        }
    }
}

/// The wide wind tile: speed, gust and direction beside the compass (web `WindHighlightTile`).
struct WeatherWindTile: View {
    var tile: WeatherHighlight
    var wind: WeatherHighlight.Wind

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var compassSize: CGFloat = 104

    var body: some View {
        WeatherTile(
            title: tile.title, symbol: WeatherSymbols.highlight(.wind), label: tile.accessibilityLabel,
            identifier: "weather.highlight.wind", value: nil
        ) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.m) { readout; compass }
            } else {
                HStack(alignment: .center, spacing: HassTokens.Spacing.m) { readout; Spacer(minLength: 0); compass }
            }
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            row(wind.speedLabel, wind.speedValue)
            row(wind.gustLabel, wind.gustValue)
            row(wind.directionLabel, wind.directionValue)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.footnote).foregroundStyle(HassTokens.Ink.onDarkSecondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private var compass: some View {
        WeatherCompass(sourceDegrees: wind.showVector ? wind.bearingDegrees : nil)
            .frame(width: min(compassSize, 160), height: min(compassSize, 160))
    }
}
