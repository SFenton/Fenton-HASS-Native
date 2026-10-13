import HassCore
import HassDesign
import SwiftUI

/// The Home weather card (web `WeatherSummary`): condition, temperature, today's range and a 24-hour carousel.
/// Opens the Weather sheet. Spec: `.agents/pages/home/spec.md`; notes: `.agents/patterns/weather.md`.
///
/// The card owns the shared ``WeatherForecastStore`` wiring: it starts fetching when it appears, refetches when the
/// weather entity updates, pauses in the background and tells the store when the websocket is ready.
struct WeatherSummaryCard: View {
    /// Opens the sheet on appearance (gallery and UI tests).
    var startsOpen = false

    @Environment(EntityStore.self) private var entities
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.weatherForecastStore) private var injectedStore
    @Environment(\.weatherForecastCaller) private var callerOverride
    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = WeatherStoreHolder()

    init(startsOpen: Bool = false) { self.startsOpen = startsOpen }

    var body: some View {
        let forecasts = injectedStore ?? holder.store(for: connection?.server)
        let weather = entities.entity(WeatherEntities.weather).state
        WeatherCardContent(forecasts: forecasts, startsOpen: startsOpen)
            .onAppear {
                if let caller = callerOverride ?? connection {
                    forecasts.activate(caller: caller, revision: WeatherForecastStore.revision(of: weather), connected: isConnected)
                }
            }
            .onDisappear { forecasts.deactivate() }
            .onChange(of: WeatherForecastStore.revision(of: weather)) { _, revision in forecasts.update(revision: revision) }
            .onChange(of: isConnected) { _, connected in forecasts.setConnected(connected) }
            .onChange(of: scenePhase) { _, phase in forecasts.setForeground(phase == .active) }
            .task(id: briefingKey(forecasts)) { await keepBriefingCurrent(forecasts) }
    }

    /// The websocket is ready. Without a connection (the gallery) forecasts come from the injected service.
    private var isConnected: Bool {
        guard let connection else { return true }
        if case .connected = connection.status { return true }
        return false
    }

    private func briefingKey(_ forecasts: WeatherForecastStore) -> [Date?] {
        [forecasts.daily.updatedAt, forecasts.hourly.updatedAt]
    }

    /// Writes the day's briefing when it is due and checks again every 30 s (web `useWeatherDayBriefing`).
    private func keepBriefingCurrent(_ forecasts: WeatherForecastStore) async {
        while !Task.isCancelled {
            let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
            let sun = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)
            let aqi = entities.entity(WeatherEntities.airQuality).state?.state
            forecasts.updateBriefing(WeatherBriefingContext(current: current, aqiState: aqi, sun: sun))
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
