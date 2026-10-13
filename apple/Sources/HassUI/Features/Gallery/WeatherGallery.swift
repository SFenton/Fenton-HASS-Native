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
#endif
