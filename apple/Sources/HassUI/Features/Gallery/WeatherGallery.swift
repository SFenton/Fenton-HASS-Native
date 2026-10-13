#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the Weather card and sheet: fixture weather entities and a fixture `weather.get_forecasts`
/// service, so journeys, audits and screenshots reach every state without the house.
///
/// Environment (all optional): `FENTON_GALLERY_WEATHER_CONDITION=<ha condition>` (default `rainy`),
/// `FENTON_GALLERY_WEATHER_NIGHT=1` (sun below the horizon), `FENTON_GALLERY_WEATHER_STATE=loading|error|empty`
/// (the service never answers, fails, or returns nothing), `FENTON_GALLERY_WEATHER_OPEN=1` (sheet open at launch),
/// `FENTON_GALLERY_WEATHER_NOAQI=1` (no air-quality sensor).
struct WeatherGallery: View {
    @State private var entities: EntityStore
    @State private var forecasts: WeatherForecastStore
    @State private var caller: WeatherFixtureCaller
    private let startsOpen: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let condition = environment["FENTON_GALLERY_WEATHER_CONDITION"] ?? "rainy"
        let store = EntityStore()
        store.replaceAll(WeatherFixtures.states(
            condition: condition, night: environment["FENTON_GALLERY_WEATHER_NIGHT"] == "1", airQuality: environment["FENTON_GALLERY_WEATHER_NOAQI"] != "1"
        ))
        _entities = State(initialValue: store)
        _forecasts = State(initialValue: WeatherForecastStore(requestTimeout: 3600))
        _caller = State(initialValue: WeatherFixtureCaller(mode: WeatherFixtureCaller.Mode(rawValue: environment["FENTON_GALLERY_WEATHER_STATE"] ?? "") ?? .normal))
        startsOpen = environment["FENTON_GALLERY_WEATHER_OPEN"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                WeatherSummaryCard(startsOpen: startsOpen)
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .accessibilityIdentifier("weather.gallery")
        .navigationTitle("Home")
        .environment(entities)
        .environment(\.weatherForecastStore, forecasts)
        .environment(\.weatherForecastCaller, caller)
    }
}

/// A `weather.get_forecasts` double that answers from ``WeatherFixtures``.
@MainActor
final class WeatherFixtureCaller: WeatherForecastCalling {
    enum Mode: String {
        case normal, loading, error, empty
    }

    struct Failure: LocalizedError {
        var errorDescription: String? { "Home Assistant could not reach Pirate Weather." }
    }

    private(set) var lastCall = "None"
    let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        let kind = WeatherForecastKind(rawValue: data["type"] as? String ?? "") ?? .daily
        lastCall = "\(domain).\(service) \(kind.rawValue)"
        switch mode {
        case .loading:
            try await Task.sleep(for: .seconds(3600))
            return .null
        case .error: throw Failure()
        case .empty: return WeatherFixtures.response([])
        case .normal: return WeatherFixtures.response(kind == .daily ? WeatherFixtures.daily() : WeatherFixtures.hourly())
        }
    }
}

/// Synthetic weather for the gallery and hosted tests (not a copy of the live house). Times are relative to now, so
/// the hourly list never expires while a journey runs.
enum WeatherFixtures {
    static func states(condition: String, night: Bool, airQuality: Bool, now: Date = Date()) -> [EntityState] {
        var states = [
            EntityState(entityId: WeatherEntities.weather, state: condition, attributes: [
                "friendly_name": .string("Pirate Weather"), "temperature": .number(72), "apparent_temperature": .number(75),
                "temperature_unit": .string("°F"), "humidity": .number(58), "wind_speed": .number(9), "wind_gust_speed": .number(14),
                "wind_speed_unit": .string("mph"), "wind_bearing": .number(250), "pressure": .number(29.92), "pressure_unit": .string("inHg"),
                "visibility": .number(10), "visibility_unit": .string("mi"), "precipitation_unit": .string("in"),
            ]),
            EntityState(entityId: WeatherEntities.sun, state: night ? "below_horizon" : "above_horizon", attributes: [
                "next_rising": .string(iso(now.addingTimeInterval(night ? 6 * 3600 : 17 * 3600))),
                "next_setting": .string(iso(now.addingTimeInterval(night ? 20 * 3600 : 5 * 3600))),
            ]),
        ]
        if airQuality { states.append(EntityState(entityId: WeatherEntities.airQuality, state: "72")) }
        return states
    }

    /// A `weather.get_forecasts` response object for the weather entity.
    static func response(_ forecasts: [JSONValue]) -> JSONValue {
        .object([WeatherEntities.weather: .object(["forecast": .array(forecasts)])])
    }

    /// 24 hours starting at the current hour: rain easing to cloud and then clearing.
    static func hourly(now: Date = Date()) -> [JSONValue] {
        let hourStart = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let conditions = ["rainy", "rainy", "pouring", "rainy", "cloudy", "cloudy", "partlycloudy", "partlycloudy", "sunny", "sunny", "clear-night", "clear-night"]
        return (0..<24).map { index in
            let wet = index < 5
            return .object([
                "datetime": .string(iso(hourStart.addingTimeInterval(Double(index) * 3600))),
                "condition": .string(conditions[(index / 2) % conditions.count]),
                "temperature": .number(72 - Double(index % 12) * 0.8),
                "apparent_temperature": .number(74 - Double(index % 12) * 0.8),
                "precipitation": .number(wet ? 0.04 + Double(index) * 0.01 : 0),
                "precipitation_probability": .number(wet ? 80 - Double(index) * 8 : 5),
                "humidity": .number(58 + Double(index % 6) * 3),
                "cloud_coverage": .number(wet ? 90 : 40),
                "wind_speed": .number(8 + Double(index % 5)),
                "wind_gust_speed": .number(14 + Double(index % 5) * 2),
                "wind_bearing": .number(250 + Double(index) * 4),
                "uv_index": .number(Double(index % 8)),
            ])
        }
    }

    /// Seven days starting today.
    static func daily(now: Date = Date()) -> [JSONValue] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: now)
        let conditions = ["rainy", "partlycloudy", "sunny", "sunny", "cloudy", "pouring", "lightning-rainy"]
        return (0..<7).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
            return .object([
                "datetime": .string(iso(day)),
                "condition": .string(conditions[index]),
                "temperature": .number(78 + Double(index % 4) * 3),
                "templow": .number(58 + Double(index % 3) * 2),
                "precipitation": .number(index == 0 || index >= 5 ? 0.3 : 0),
                "precipitation_probability": .number(index == 0 ? 70 : index >= 5 ? 60 : 10),
                "wind_speed": .number(8 + Double(index)),
                "wind_gust_speed": .number(15 + Double(index) * 2),
                "wind_bearing": .number(220 + Double(index) * 20),
                "uv_index": .number(7),
            ])
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
#endif
