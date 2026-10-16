import Foundation
@testable import HassCore
@testable import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// What each status chip draws for the house's state (`.agents/patterns/status-rail.md`, "Chip colours"): Climate and
/// Air Quality follow Home Assistant's colours, Occupancy fills its person, Contact Sensors read the house.
@MainActor
struct StatusChipAppearanceTests {
    /// A lookup over fixed states.
    private func lookup(_ states: [String: String]) -> EntityLookup {
        { id in states[id].map { EntityState(entityId: id, state: $0) } }
    }

    private func chip(_ sheet: HomeConfig.ChipSheet) -> HomeConfig.StatusChip {
        HomeConfig.statusChips.first { $0.sheet == sheet }!
    }

    private func home(_ sheet: HomeConfig.ChipSheet, _ states: [String: String]) -> StatusChipAppearance {
        StatusChipAppearance.home(chip(sheet), read: lookup(states))
    }

    private let allContacts = "binary_sensor.contact_sensors"

    // MARK: Climate

    @Test func climateFollowsTheTemperatureColour() {
        let cold = home(.climate, ["input_text.all_climate_color": "rgba(0, 110, 255, 1)", "input_text.all_climate_range": "50°F"])
        let mild = home(.climate, ["input_text.all_climate_color": "rgba(158, 209, 46, 1)"])
        let hot = home(.climate, ["input_text.all_climate_color": "rgba(255, 0, 0, 1)"])
        #expect(cold.isFilled && mild.isFilled && hot.isFilled, "Climate always fills")
        #expect(Set([cold.tint, mild.tint, hot.tint].compactMap { $0?.fill }).count == 3, "Each temperature has its own fill")
        #expect(cold.tint == ChipTint.fromWeb(0x006EFF, preferredGlyph: 0xFFCC00))
        #expect(cold.symbol == SymbolMap.symbol(for: "mdi:thermometer"))
    }

    @Test func climateFallsBackToTheGradientThenToNavy() {
        let gradient = home(.climate, ["input_text.all_climate_range": "74°F"])
        #expect(gradient.tint == ChipTint.fromWeb(0xFFD700, preferredGlyph: 0xFFCC00), "The web gradient at 74°F")
        let none = home(.climate, [:])
        #expect(none.tint == nil && none.family == .climate && none.isFilled, "The family navy")
    }

    // MARK: Air quality

    @Test func airQualityColoursFillAndGlyphWithTheAQIColour() {
        let good = home(.airQuality, ["input_text.all_aqi_color": "rgba(0, 150, 136, 1)"])
        let poor = home(.airQuality, ["input_text.all_aqi_color": "rgba(255, 126, 0, 1)"])
        #expect(ChipTint.isClose(good.tint?.fill ?? 0, ColorFamily.air.spec.fill ?? 1), "Good air keeps the web teal")
        #expect(poor.tint == ChipTint.fromWeb(0xFF7E00))
        #expect(good.tint != poor.tint)
        #expect(good.isFilled && poor.isFilled)
        #expect(home(.airQuality, [:]).tint == ChipTint.fromWeb(ChipWebColor.airTeal.rgb), "No helper yet: the teal")
    }

    @Test func airQualitySummaryKeepsTheWebWording() {
        let summary = HomeConfig.summary(for: chip(.airQuality)) { id in
            ["input_text.all_aqi_range": "18", "input_text.all_pm25_range": "1µg/m³ - 3µg/m³"][id]
                .map { EntityState(entityId: id, state: $0) }
        }
        #expect(summary == "AQI 18 · PM2.5 1µg/m³ - 3µg/m³", "AtAGlancePage.tsx:1187")
    }

    // MARK: Occupancy

    @Test func occupancyDrawsAnOutlinePersonWhenClearAndAFilledOneWhenDetected() {
        let clear = home(.occupancy, ["binary_sensor.occupancy_sensors": "off"])
        let detected = home(.occupancy, ["binary_sensor.occupancy_sensors": "on"])
        #expect(clear.symbol == "person" && detected.symbol == "person", "One symbol; the chip fills it while detected")
        #expect(!clear.isFilled && detected.isFilled)
        #expect(detected.family == .occupancy && detected.tint == nil)
        #expect(!home(.occupancy, [:]).isFilled)
    }

    /// The web tints Occupancy by detection alone (`StatusRail.tsx:41-46`): not by the alarm or by who is home.
    @Test func occupancyIgnoresTheAlarmAndTheAwayMode() {
        let base = home(.occupancy, ["binary_sensor.occupancy_sensors": "on"])
        for alarm in ["disarmed", "armed_home", "armed_away", "armed_night", "triggered"] {
            for away in ["Home", "Away"] {
                let states = ["binary_sensor.occupancy_sensors": "on", SecurityConfig.alarmEntityId: alarm,
                              ClimateConfig.homeAwayEntityId: away]
                #expect(home(.occupancy, states) == base, "\(alarm) \(away)")
            }
        }
    }

    // MARK: Contact sensors

    @Test func contactChipShowsAColourWhenEverythingIsClosed() {
        let closed = home(.contacts, [allContacts: "off"])
        #expect(closed.isFilled && closed.tint == .contactClosed)
        #expect(closed.symbol == "door.left.hand.closed")
    }

    @Test func contactChipReadsTheHouseWhenSomethingIsOpen() {
        let sensor = RoomOverview.contactEntityIds[0]
        func appearance(alarm: String, away: String) -> StatusChipAppearance {
            home(.contacts, [sensor: "on", SecurityConfig.alarmEntityId: alarm, ClimateConfig.homeAwayEntityId: away])
        }
        let atHome = appearance(alarm: "disarmed", away: "Home")
        #expect(atHome.tint == .contactOpenHome && atHome.symbol == "door.left.hand.open")
        let away = appearance(alarm: "disarmed", away: "Away")
        #expect(away.tint == .contactOpenAway && away.symbol == "door.left.hand.open")
        for mode in ["armed_home", "armed_away", "armed_night", "triggered"] {
            let armed = appearance(alarm: mode, away: "Home")
            #expect(armed.tint == .contactOpenArmed, "\(mode)")
            #expect(armed.symbol == "exclamationmark.triangle", "An alert glyph, not colour alone")
            #expect(appearance(alarm: mode, away: "Away").tint == .contactOpenArmed, "Armed outranks away")
        }
    }

    @Test func contactStatesNeverShareAFillOrAGlyphWithAnotherState() {
        let states: [ContactChipState] = [.allClosed, .openHome, .openAway, .openArmed]
        let looks = states.map { StatusChipAppearance.contact($0, fallbackSymbol: "door") }
        #expect(Set(looks.compactMap { $0.tint?.fill }).count == 4)
        #expect(Set(looks.map(\.symbol)).count == 3, "Closed, open and alert glyphs")
        let unavailable = StatusChipAppearance.contact(.unavailable, fallbackSymbol: "door")
        #expect(!unavailable.isFilled && unavailable.tint == nil && unavailable.symbol == "door")
    }

    // MARK: Lights and Security keep the family colours

    @Test func lightsAndSecurityKeepTheirFamilies() {
        #expect(home(.lights, ["light.lights": "on"]).isFilled)
        #expect(!home(.lights, ["light.lights": "off"]).isFilled)
        let armed = home(.security, [SecurityConfig.alarmEntityId: "armed_away"])
        #expect(armed.family == .securityAway && armed.isFilled)
        #expect(!home(.security, [SecurityConfig.alarmEntityId: "arming"]).isFilled)
        #expect(home(.security, [:]).family == nil)
    }

    // MARK: Rooms

    private func roomCard(_ kind: RoomCardKind, entity: String = "x") -> RoomCard {
        RoomCard("Card", entity, icon: "mdi:door", kind: kind)
    }

    private func display(_ card: RoomCard, active: Bool = false, contact: ContactChipState? = nil, color: RoomColor? = nil) -> RoomChipDisplay {
        RoomChipDisplay(title: card.title, summary: "", icon: card.icon, isActive: active, opensSheet: true, contact: contact, webColor: color)
    }

    @Test func roomContactChipsUseTheSharedStates() {
        let card = roomCard(.contact)
        for (state, tint) in [(ContactChipState.allClosed, ChipTint.contactClosed), (.openHome, .contactOpenHome),
                              (.openAway, .contactOpenAway), (.openArmed, .contactOpenArmed)] {
            let look = StatusChipAppearance.room(card, chip: display(card, contact: state))
            #expect(look.tint == tint && look.isFilled)
        }
        #expect(!StatusChipAppearance.room(card, chip: display(card, contact: .unavailable)).isFilled)
    }

    @Test func roomOccupancyAndClimateAndAirChips() {
        let occupancy = roomCard(.occupancy)
        #expect(StatusChipAppearance.room(occupancy, chip: display(occupancy, active: true)).isFilled)
        #expect(!StatusChipAppearance.room(occupancy, chip: display(occupancy, active: false)).isFilled)
        #expect(StatusChipAppearance.room(occupancy, chip: display(occupancy)).symbol == "person")

        let climate = roomCard(.climate)
        let warm = StatusChipAppearance.room(climate, chip: display(climate, color: RoomColor(255, 215, 0)))
        #expect(warm.tint == ChipTint.fromWeb(0xFFD700, preferredGlyph: 0xFFCC00) && warm.isFilled)
        let bed = StatusChipAppearance.room(climate, chip: display(climate))
        #expect(bed.tint == nil && bed.family == .climate && bed.isFilled, "Without a colour: the family navy")

        let air = roomCard(.air)
        let aqi = StatusChipAppearance.room(air, chip: display(air, color: RoomColor(255, 126, 0)))
        #expect(aqi.tint == ChipTint.fromWeb(0xFF7E00) && aqi.isFilled)
        #expect(StatusChipAppearance.room(air, chip: display(air)).isFilled)

        let lights = roomCard(.light)
        #expect(!StatusChipAppearance.room(lights, chip: display(lights, active: false)).isFilled)
    }

    // MARK: Contrast

    /// Every state a chip can draw keeps its white title and state at 4.5:1 and its glyph at 3:1.
    @Test func everyChipLookReads() {
        var tints: [ChipTint] = [.contactClosed, .contactOpenHome, .contactOpenAway, .contactOpenArmed]
        tints += [0x006EFF, 0x8000FF, 0x00C878, 0xFFD700, 0xFFA500, 0xFF0000].compactMap { StatusChipAppearance.climate(RoomColor.rgb($0)) }
        tints += [0x009688, 0xFFFF00, 0xFF7E00, 0xFF0000, 0x8F3F97, 0x7E0023].map { StatusChipAppearance.air(RoomColor.rgb($0)) }
        for tint in tints {
            #expect(ChipTint.contrast(0xFFFFFF, tint.fill) >= 4.5)
            #expect(ChipTint.contrast(0xFFFFFF, tint.liftedFill) >= 4.5)
            #expect(ChipTint.contrast(tint.glyph, tint.liftedFill) >= 3)
        }
    }

    @Test func chipsRenderWithTheirLooks() {
        let contact = StatusChipAppearance.contact(.openArmed, fallbackSymbol: "door")
        let view = StatusChipButton(title: "Contact Sensors", summary: "1 Open", symbol: contact.symbol, family: contact.family,
                                    isActive: contact.isFilled, tint: contact.tint, action: {})
        #expect(ImageRenderer(content: view).cgImage != nil)
    }
}

private extension RoomColor {
    /// A colour from `0xRRGGBB`.
    static func rgb(_ value: UInt32) -> RoomColor {
        RoomColor(Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
    }
}
