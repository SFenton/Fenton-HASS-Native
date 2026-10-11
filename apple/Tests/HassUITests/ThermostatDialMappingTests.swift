import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Climate entity → dial mapping, against the web's `ThermostatDial` reads
/// (`ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:4188`).
@MainActor
struct ThermostatDialMappingTests {
    @Test func singleTargetEntity() {
        let entity = EntityState(entityId: "climate.office", state: "heat", attributes: [
            "current_temperature": .number(68.5), "temperature": .number(72), "hvac_action": .string("heating"),
            "min_temp": .number(50), "max_temp": .number(90), "target_temp_step": .number(1),
        ])
        let config = ThermostatDialConfiguration(entity: entity, title: "Office")
        #expect(config.targets == .single(72))
        #expect(config.current == 68.5)
        #expect(config.action == "heating")
        #expect(config.min == 50 && config.max == 90 && config.step == 1)
        #expect(config.unit == "°F")
        #expect(!config.isUnavailable && !config.isOff)
    }

    @Test func rangeEntityAndDefaults() {
        let entity = EntityState(entityId: "climate.home", state: "heat_cool", attributes: [
            "target_temp_low": .number(68), "target_temp_high": .number(75), "temperature": .null,
            "temperature_unit": .string("°C"),
        ])
        let config = ThermostatDialConfiguration(entity: entity, title: "Home")
        #expect(config.targets == .range(low: 68, high: 75))
        #expect(config.action == "heat_cool")
        #expect(config.min == 45 && config.max == 95 && config.step == 0.5)
        #expect(config.unit == "°C")
    }

    @Test func missingOrUnavailableEntities() {
        #expect(ThermostatDialConfiguration(entity: nil, title: "Gone").isUnavailable)
        let unavailable = ThermostatDialConfiguration(entity: EntityState(entityId: "climate.x", state: "unavailable"), title: "X")
        #expect(unavailable.isUnavailable)
        #expect(unavailable.targets == nil)
        let off = ThermostatDialConfiguration(entity: EntityState(entityId: "climate.x", state: "off", attributes: ["temperature": .number(66)]), title: "X")
        #expect(off.isOff && off.isInactive)
        let unit = ThermostatDialConfiguration(entity: EntityState(entityId: "climate.x", state: "off", attributes: ["unit_of_measurement": .string("°C")]), title: "X")
        #expect(unit.unit == "°C")
    }

    @Test func setTemperatureDataTargetsOneOrManyEntities() {
        let one = ThermostatTargets.single(72).setTemperatureData(entityIds: ["climate.office"])
        #expect(one["entity_id"] as? String == "climate.office")
        #expect(one["temperature"] as? Double == 72)
        let many = ThermostatTargets.range(low: 68, high: 75).setTemperatureData(entityIds: ["climate.a", "climate.b"])
        #expect(many["entity_id"] as? [String] == ["climate.a", "climate.b"])
        #expect(many["target_temp_low"] as? Double == 68)
    }

    /// A bound dial commits to its own entity, or fans out to `commitEntityIds` (the web's global thermostat).
    @Test func boundDialCommitsToItsEntityOrTheFanOut() {
        let own = ClimateThermostatDial(entityId: "climate.office", title: "Office")
            .setTemperatureData(for: .single(71.5))
        #expect(own["entity_id"] as? String == "climate.office")
        #expect(own["temperature"] as? Double == 71.5)
        let fanOut = ClimateThermostatDial(entityId: "climate.whole_home", title: "Whole Home") { targets in
            #expect(targets == .range(low: 67, high: 76))
            return ["climate.office", "climate.living_room"]
        }
        let data = fanOut.setTemperatureData(for: .range(low: 67, high: 76))
        #expect(data["entity_id"] as? [String] == ["climate.office", "climate.living_room"])
        #expect(data["target_temp_low"] as? Double == 67)
        #expect(data["target_temp_high"] as? Double == 76)
    }

    /// The bound dial renders from a snapshot-only store.
    @Test func boundDialRendersFromTheStore() throws {
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "dial-\(UUID()).json"))
        try cache.save([
            EntityState(entityId: "climate.office", state: "heat", attributes: ["current_temperature": .number(70), "temperature": .number(72)]),
        ], server: .fentonHome)
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store, snapshotCache: cache)
        let view = ClimateThermostatDial(entityId: "climate.office", title: "Office", size: .modal, commitEntityIds: { _ in ["climate.office"] })
            .environment(connection)
            .environment(store)
            .frame(width: 360, height: 360)
        #expect(ImageRenderer(content: view).cgImage != nil)
        cache.clear()
    }

    @Test func galleryRendersEveryFixture() {
        #expect(ComponentGallery.requested == nil)
        #expect(ThermostatDialGallery.fixtures.map(\.id) == ["heating", "range", "cooling", "off", "unavailable"])
        #expect(ThermostatDialGallery.describe(.single(72.5)) == "single 72.5")
        #expect(ThermostatDialGallery.describe(.range(low: 68, high: 75)) == "range 68-75")
        let view = ComponentGallery(page: .thermostatDial).frame(width: 402, height: 1600)
        #expect(ImageRenderer(content: view).cgImage != nil)
    }
}
