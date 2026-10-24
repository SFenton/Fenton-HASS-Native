import Foundation
@testable import HassCore
import Testing

/// Room pages: config parity with the web, the room grid's ranking, state text, and what each card shows, opens
/// and sends.
@MainActor
struct RoomsTests {
    func controller(_ id: String, _ states: [String: String], attributes: [String: [String: JSONValue]] = [:])
        -> (RoomController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let page = RoomsConfig.page(id: id)!
        return (RoomController(page: page, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    func card(_ page: String, _ title: String) -> RoomCard {
        RoomsConfig.page(id: page)!.allCards.first { $0.title == title }!
    }

    // MARK: Config parity

    @Test func sixteenRoomsInWebOrderMatchTheRoomGrid() {
        #expect(RoomsConfig.pages.count == 16)
        #expect(Set(RoomsConfig.pages.map(\.id)) == Set(RoomNavigation.items.map(\.path)))
        #expect(RoomsConfig.pages.first?.id == "living-room")
        #expect(RoomsConfig.pages.last?.id == "entryway")
        for page in RoomsConfig.pages {
            #expect(RoomNavigation.item(for: page.id)?.title == page.title, "\(page.id)")
            #expect(Set(page.allCards.map(\.id)).count == page.allCards.count, "\(page.id) has duplicate card ids")
        }
    }

    @Test func everyRemoteAPageUsesExists() {
        for page in RoomsConfig.pages {
            for id in page.remoteIds { #expect(MediaRemotes.config(id: id) != nil, "\(page.id) → \(id)") }
        }
    }

    @Test func hiddenSectionsStayOffThePage() {
        let music = RoomsConfig.page(id: "music-room")!
        #expect(music.sections.contains { $0.title == "Quick App Launch" })
        #expect(!music.visibleSections.contains { $0.title == "Quick App Launch" })
        #expect(music.optimisticRemoteId == "music-room-remote")
    }

    @Test func roomsWithoutSectionsAreEmpty() {
        for id in ["hallway", "entryway"] { #expect(RoomsConfig.page(id: id)!.visibleSections.isEmpty) }
    }

    // MARK: Room grid ranking

    @Test func mostVisitedRoomsComeFirstAndTiesKeepConfigOrder() {
        let counts = ["counter.room_access_kitchen": "12", "counter.room_access_gym": "3.0", "counter.room_access_office": "3"]
        let ranked = RoomNavigation.ranked { counts[$0] }.map(\.path)
        #expect(Array(ranked.prefix(3)) == ["kitchen", "gym", "office"])
        #expect(ranked[3] == "living-room")
        #expect(ranked.count == 16)
    }

    /// The grid re-ranks as Home Assistant's counters change: a visit counted by the script reaches the store through the
    /// websocket, and the next read puts that room first. Equal counts keep the configured order. The counters live in
    /// Home Assistant, so a cold launch from the disk snapshot ranks the same way.
    @Test func theGridReRanksAsVisitCountersChange() {
        let store = EntityStore()
        func counter(_ path: String, _ count: Int) -> EntityState {
            EntityState(entityId: RoomNavigation.item(for: path)!.accessCounterEntityId, state: String(count))
        }
        func ranked(_ store: EntityStore) -> [String] { RoomNavigation.ranked { store.entity($0).state?.state }.map(\.path) }
        #expect(ranked(store) == RoomNavigation.items.map(\.path), "No counters: configured order")
        store.replaceAll([counter("gym", 4), counter("office", 4), counter("kitchen", 1)])
        #expect(Array(ranked(store).prefix(3)) == ["gym", "office", "kitchen"])
        store.apply([counter("kitchen", 5)])
        #expect(Array(ranked(store).prefix(3)) == ["kitchen", "gym", "office"])
        store.apply([counter("office", 6)])
        #expect(Array(ranked(store).prefix(3)) == ["office", "kitchen", "gym"])
        let restored = EntityStore()
        restored.replaceAll(Array(store.allValues.values), freshness: .snapshot(savedAt: Date()))
        #expect(ranked(restored) == ranked(store))
    }

    @Test func unreadableCountersCountAsZero() {
        #expect(RoomNavigation.accessCount(nil) == 0)
        #expect(RoomNavigation.accessCount("unavailable") == 0)
        #expect(RoomNavigation.accessCount("-2") == 0)
        #expect(RoomNavigation.accessCount("7") == 7)
    }

    @Test func openingARoomCountsTheVisit() async {
        let caller = RecordingCaller()
        let item = RoomNavigation.item(for: "music-room")!
        #expect(item.accessCounterEntityId == "counter.room_access_music_room")
        try? await caller.call(RoomNavigation.accessIncrementCall(for: item))
        #expect(caller.calls.first?.domain == "script")
        #expect(caller.calls.first?.service == "turn_on")
        #expect(caller.calls.first?.data["entity_id"] == "script.increment_room_access")
        #expect(caller.calls.first?.data["variables"]?.contains("music-room") == true)
    }

    // MARK: Quick Links

    @Test func sprinklersShowOnlyWhenEnabled() {
        #expect(!QuickLinks.visible { _ in "off" }.contains { $0.id == "sprinklers" })
        #expect(QuickLinks.visible { $0 == SprinklersConfig.visibilityEntityId ? "on" : nil }.contains { $0.id == "sprinklers" })
        #expect(QuickLinks.visible { _ in nil }.count == 6)
    }

    @Test func foodSubtitleUsesTheTotalElseTheSpaces() {
        #expect(QuickLinks.allFoodSubtitle { [QuickLinks.totalItemsEntityId: "12", QuickLinks.expiringSoonEntityId: "2"][$0] }
            == "12 Items • 2 Expiring Soon")
        let spaces = Dictionary(uniqueKeysWithValues: QuickLinks.foodSpaceEntityIds.map { ($0, "1") })
        #expect(QuickLinks.allFoodSubtitle { spaces[$0] } == "\(QuickLinks.foodSpaceEntityIds.count) \(QuickLinks.foodSpaceEntityIds.count == 1 ? "Item" : "Items") • 0 Expiring Soon")
        #expect(QuickLinks.allFoodSubtitle { _ in nil } == "0 Items • 0 Expiring Soon")
    }

    @Test func securityLooksFollowTheAlarm() {
        #expect(QuickLinks.securityAppearance("armed_away").icon == "mdi:shield")
        #expect(QuickLinks.securityAppearance("disarmed").icon == "mdi:shield-off")
        #expect(QuickLinks.securityAppearance("triggered").icon == "mdi:shield-alert")
    }

    @Test func groceriesSubtitleCountsItems() {
        #expect(RoomsConfig.Groceries.subtitle(count: "0") == "No groceries listed")
        #expect(RoomsConfig.Groceries.subtitle(count: "1") == "1 item")
        #expect(RoomsConfig.Groceries.subtitle(count: "4") == "4 items")
        #expect(RoomsConfig.Groceries.subtitle(count: nil) == "No groceries listed")
    }

    // MARK: Formatting

    @Test func compactStatesMatchTheWeb() {
        #expect(RoomFormat.compact(nil) == "Unavailable")
        #expect(RoomFormat.compact(EntityState(entityId: "binary_sensor.contact_front", state: "on")) == "Open")
        #expect(RoomFormat.compact(EntityState(entityId: "binary_sensor.motion", state: "off")) == "Clear")
        #expect(RoomFormat.compact(EntityState(entityId: "light.kitchen", state: "on")) == "On")
        #expect(RoomFormat.compact(EntityState(entityId: "sensor.temp", state: "71.2")) == "71.2")
        // A status word is title-cased; a time, a range and a unit are left alone.
        #expect(RoomFormat.compact(EntityState(entityId: "sensor.master_bedroom_wake_light", state: "scheduled")) == "Scheduled")
        #expect(RoomFormat.compact(EntityState(entityId: "sensor.master_bedroom_wake_light", state: "6:45 AM")) == "6:45 AM")
        #expect(RoomFormat.compact(EntityState(entityId: "input_text.all_aqi_range", state: "21-34")) == "21-34")
        #expect(RoomFormat.compact(EntityState(entityId: "vacuum.x", state: "returning")) == "Returning")
    }

    @Test func occupancyAndContactWords() {
        #expect(RoomFormat.occupancy(EntityState(entityId: "binary_sensor.a", state: "on")) == "Detected")
        #expect(RoomFormat.occupancy(EntityState(entityId: "binary_sensor.a", state: "off")) == "Clear")
        #expect(RoomFormat.contact(EntityState(entityId: "binary_sensor.a", state: "on")) == "Open")
        #expect(RoomFormat.contact(EntityState(entityId: "binary_sensor.a", state: "off")) == "Closed")
        #expect(RoomFormat.contact(EntityState(entityId: "binary_sensor.a", state: "unknown")) == "Unknown")
    }

    @Test func unitsAndAirSummaries() {
        let humidity = EntityState(entityId: "sensor.h", state: "45", attributes: ["unit_of_measurement": .string("%")])
        #expect(RoomFormat.withUnit(humidity) == "45%")
        #expect(RoomFormat.aqiEntityId(forPM25: "sensor.office_air_purifier_pm2_5") == "sensor.office_air_purifier_air_quality_index")
        let pm = EntityState(entityId: "sensor.p", state: "12", attributes: ["unit_of_measurement": .string("µg/m³")])
        let aqi = EntityState(entityId: "sensor.q", state: "40.0")
        #expect(RoomFormat.airSummary(aqi: aqi, pm25: pm) == "40 • 12 µg/m³")
        #expect(RoomFormat.temperature(EntityState(entityId: "sensor.t", state: "70", attributes: ["unit_of_measurement": .string("°F")])) == "70°F")
    }

    @Test func contactSummariesNameWhatIsOpen() {
        let group = RoomGroup("Test", entityId: "binary_sensor.test", [
            RoomGroupItem("Front Door", "binary_sensor.front"),
            RoomGroupItem("Back Door", "binary_sensor.back"),
            RoomGroupItem("Window", "binary_sensor.window"),
        ])
        func summary(_ open: Set<String>) -> String {
            RoomFormat.contactSummary(group) { EntityState(entityId: $0, state: open.contains($0) ? "on" : "off") }
        }
        #expect(summary([]) == "All Closed")
        #expect(summary(["binary_sensor.front"]) == "1 Door Open")
        #expect(summary(["binary_sensor.front", "binary_sensor.back"]) == "All Doors Open")
        #expect(summary(["binary_sensor.window", "binary_sensor.front"]) == "Window Open, 1 Door Open")
    }

    // MARK: Cards

    @Test func lightCardsDimWhileOff() {
        let (room, store, _, _) = controller("kitchen", ["light.kitchen": "off"])
        let lights = card("kitchen", "Lights")
        #expect(room.display(lights).isOff)
        #expect(room.display(lights).subtitle == "Off")
        #expect(room.display(lights).semantics == .modal)
        set(store, "light.kitchen", "on")
        #expect(!room.display(lights).isOff)
    }

    @Test func unavailableCardsAreDisabled() {
        let (room, _, caller, _) = controller("guest-bathroom", [:])
        let towel = card("guest-bathroom", "Towel Rack")
        let display = room.display(towel)
        #expect(display.isUnavailable)
        #expect(!display.isEnabled)
        #expect(room.tap(towel) == .none)
        #expect(caller.calls.isEmpty)
    }

    @Test func flipShowsTheNewStateAtOnceAndRollsBackOnFailure() async {
        let id = "switch.guest_bathroom_towel_rack_switch_top"
        let (room, _, caller, scheduler) = controller("guest-bathroom", [id: "off"])
        let towel = card("guest-bathroom", "Towel Rack")
        #expect(room.tap(towel) == .ran)
        #expect(room.display(towel).semantics == .toggle(isOn: true), "Optimistic on before Home Assistant answers")
        #expect(room.displayedState(id) == "on")
        await room.waitForCalls()
        scheduler.fireAll()
        #expect(room.displayedState(id) == "off", "Gives way to live state when never confirmed")

        caller.failNext = true
        #expect(room.tap(towel) == .ran)
        #expect(room.displayedState(id) == "on")
        await room.waitForCalls()
        #expect(room.displayedState(id) == "off", "A failed call rolls back without waiting for the timer")
    }

    @Test func flipFollowsALiveRevert() async {
        let id = "switch.guest_bathroom_towel_rack_switch_top"
        let (room, store, _, _) = controller("guest-bathroom", [id: "off"])
        room.tap(card("guest-bathroom", "Towel Rack"))
        await room.waitForCalls()
        // Something else turned it back off: any live change clears the optimistic value.
        set(store, id, "unavailable")
        for _ in 0..<5 { await Task.yield() }
        #expect(room.displayedState(id) == "unavailable")
    }

    @Test func towelRackUsesExplicitTurnOnAndOff() async {
        let id = "switch.guest_bathroom_towel_rack_switch_top"
        let (room, store, caller, _) = controller("guest-bathroom", [id: "off"])
        let towel = card("guest-bathroom", "Towel Rack")
        #expect(room.display(towel).semantics == .toggle(isOn: false))
        #expect(room.tap(towel) == .ran)
        await room.waitForCalls()
        set(store, id, "on")
        #expect(room.display(towel).background == RoomsConfig.towelRackOn)
        #expect(room.tap(towel) == .ran)
        await room.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_on", "turn_off"])
        #expect(caller.calls.allSatisfy { $0.domain == "switch" && $0.data["entity_id"] == id })
    }

    @Test func pcCardsPressTheMatchingButton() async {
        let (room, store, caller, _) = controller("office", ["input_boolean.stephen_s_pc_power": "off", "input_text.stephen_s_pc_power_state": "Off"])
        let pc = card("office", "Stephen's PC")
        #expect(room.display(pc).subtitle == "Off")
        room.tap(pc)
        await room.waitForCalls()
        set(store, "input_boolean.stephen_s_pc_power", "on")
        room.tap(pc)
        await room.waitForCalls()
        #expect(caller.calls.map(\.data["entity_id"]) == ["input_button.stephen_s_pc_on", "input_button.stephen_s_pc_off"])
    }

    @Test func personalTitlesFollowTheViewer() {
        let (room, _, _, _) = controller("office", [:])
        let pc = card("office", "Stephen's PC")
        #expect(room.display(pc, viewer: .stephen).title == "Your PC")
        #expect(room.display(pc, viewer: .steph).title == "Stephen's PC")
        #expect(room.display(pc).title == "Stephen's PC")
        let bed = card("master-bedroom", "Steph's Bed")
        #expect(bed.title(for: .steph) == "Your Side")
        #expect(bed.title(for: .stephen) == "Steph's Side")
    }

    @Test func bedsTakeTheirClimateActionWash() {
        let id = "climate.sleepypod_eight_pod_left_side"
        let (room, _, _, _) = controller("master-bedroom", [id: "heat_cool"], attributes: [id: ["hvac_action": .string("heating")]])
        #expect(room.display(card("master-bedroom", "Stephen's Bed")).background == RoomColor(136, 64, 26, opacity: 0.6))
    }

    @Test func musicRoomSourcesShareTheRemotesOptimisticState() async {
        typealias M = MediaRemotes.MusicRoom
        let (room, _, caller, _) = controller("music-room", [M.controlEntityId: "on", M.activeMediaSourceEntityId: M.Source.server])
        let xbox = card("music-room", "Xbox")
        #expect(room.display(xbox).semantics == .selection(isSelected: false))
        #expect(room.tap(xbox) == .ran)
        await room.waitForCalls()
        #expect(!caller.calls.isEmpty)
        #expect(room.remote("music-room-remote") != nil)
    }

    // MARK: Chips

    @Test func occupancyChipSwapsItsIcon() {
        let (room, store, _, _) = controller("kitchen", [:])
        let occupancy = RoomsConfig.page(id: "kitchen")!.overviewCards.first { $0.kind == .occupancy }!
        set(store, occupancy.entityId, "off")
        #expect(room.chip(occupancy).summary == "Clear")
        #expect(room.chip(occupancy).icon == "mdi:motion-sensor-off")
        set(store, occupancy.entityId, "on")
        #expect(room.chip(occupancy).summary == "Detected")
        #expect(room.chip(occupancy).isActive)
    }

    @Test func pluralContactChipsReadAllClosed() {
        let (room, store, _, _) = controller("garage", ["binary_sensor.garage_doors": "off"])
        let doors = card("garage", "Doors")
        #expect(room.chip(doors).summary == "All Closed")
        set(store, "binary_sensor.garage_doors", "on")
        #expect(room.chip(doors).summary == "Open")
        #expect(room.chip(doors).icon == "mdi:door-open")
    }

    /// Owner, 2026-10-16: a contact chip says whether the house is closed, open with someone home, open while away, or open
    /// while the system is armed; the alarm outranks being away.
    @Test func roomContactChipsFollowTheHouse() {
        let (room, store, _, _) = controller("garage", ["binary_sensor.garage_doors": "off"])
        let doors = card("garage", "Doors")
        #expect(room.chip(doors).contact == .allClosed)
        set(store, "binary_sensor.garage_doors", "on")
        #expect(room.chip(doors).contact == .openHome)
        set(store, ClimateConfig.homeAwayEntityId, "Away")
        #expect(room.chip(doors).contact == .openAway)
        set(store, SecurityConfig.alarmEntityId, "armed_night")
        #expect(room.chip(doors).contact == .openArmed)
        set(store, SecurityConfig.alarmEntityId, "disarmed")
        set(store, ClimateConfig.homeAwayEntityId, "Home")
        #expect(room.chip(doors).contact == .openHome)
        set(store, "binary_sensor.garage_doors", "unavailable")
        #expect(room.chip(doors).contact == .unavailable)
        #expect(room.chip(card("garage", "Doors")).webColor == nil)
    }

    @Test func roomClimateAndAirChipsCarryTheWebColour() {
        let (room, store, _, _) = controller("living-room", [:])
        let climate = card("living-room", "Climate")
        let air = card("living-room", "Air Quality")
        #expect(room.chip(climate).webColor == nil, "No helper and no range: the family navy")
        set(store, climate.entityId, "70.0°F - 74.0°F")
        #expect(room.chip(climate).webColor == RoomOverview.colorFromTemperature(72), "The gradient at the range's mean")
        set(store, "input_text.living_room_climate_color", "rgba(158, 209, 46, 1)")
        #expect(room.chip(climate).webColor == RoomColor(158, 209, 46), "The helper wins")
        #expect(room.chip(air).webColor == ChipWebColor.airTeal, "No AQI helper yet: the web teal")
        set(store, "input_text.living_room_aqi_color", "rgba(255, 190, 0, 1)")
        #expect(room.chip(air).webColor == RoomColor(255, 190, 0))
        #expect(room.chip(card("living-room", "Lights")).webColor == nil)
    }

    // MARK: Sheets

    @Test func sheetsRouteByKind() {
        let (living, _, _, _) = controller("living-room", [:])
        let page = RoomsConfig.page(id: "living-room")!
        func sheet(_ title: String) -> RoomSheetContent { living.sheet(for: page.allCards.first { $0.title == title }!) }
        #expect(sheet("Living Room Remote") == .mediaRemote(id: "living-room-shield"))
        if case .lights = sheet("Lights") {} else { Issue.record("Lights sheet") }
        if case .occupancy = sheet("Occupancy") {} else { Issue.record("Occupancy sheet") }
        if case .items = sheet("Vents") {} else { Issue.record("Vents sheet") }
        #expect(sheet("Main Floor") == .device(.vacuum(entityId: "vacuum.valetudo_exaltedsneakydeer")))
        #expect(sheet("Air Quality") == .device(.airQuality(pm25EntityId: "sensor.living_room_air_purifier_pm2_5")))

        let (bedroom, _, _, _) = controller("master-bedroom", [:])
        #expect(bedroom.sheet(for: card("master-bedroom", "Stephen's Bed"))
            == .device(.bed(sheet: "stephens-bed", climateEntityId: "climate.sleepypod_eight_pod_left_side")))
        #expect(bedroom.sheet(for: card("master-bedroom", "Humidifier")) == .device(.humidifier(powerEntityId: RoomsConfig.Humidifier.powerEntityId)))
        #expect(bedroom.sheet(for: card("master-bedroom", RoomsConfig.WakeLight.title))
            == .device(.wakeLight(statusEntityId: RoomsConfig.WakeLight.statusEntityId)))

        let (bath, _, _, _) = controller("guest-bathroom", [:])
        #expect(bath.sheet(for: card("guest-bathroom", "Fan")) == .device(.bathroomFan(powerEntityId: RoomsConfig.BathroomFan.guestPower)))
        #expect(bath.sheet(for: card("guest-bathroom", "Towel Rack")) == .fallback)
    }

    @Test func sheetTitlesAndSubtitles() {
        let (living, store, _, _) = controller("living-room", [:])
        #expect(living.sheetTitle(for: card("living-room", "Lights")) == "Living Room Lights")
        #expect(living.sheetTitle(for: card("living-room", "Main Floor")) == "Living Room: Robot Vacuum")
        #expect(living.sheetSubtitle(for: card("living-room", "Lights")) == nil)
        let occupancy = card("living-room", "Occupancy")
        #expect(living.sheetSubtitle(for: occupancy) == "Clear")
        if let first = RoomGroups.occupancy(room: "Living Room")?.items.first {
            set(store, first.entityId, "on")
            #expect(living.sheetSubtitle(for: occupancy) == "Occupied")
        }
    }

    @Test func deviceFallbacksListEveryEntityOnce() {
        let (living, _, _, _) = controller("living-room", [:])
        let purifier = card("living-room", "Air Purifier")
        #expect(living.fallbackEntityIds(for: purifier) == [
            "sensor.living_room_air_purifier_pm2_5", "sensor.living_room_air_purifier_air_quality_index",
            "select.living_room_air_purifier_fan_mode", "fan.living_room_air_purifier_levoit_purifier",
        ])
    }

    @Test func roomsWithoutContactGroupsOpenEveryContact() {
        let (garage, _, _, _) = controller("garage", [:])
        let doors = card("garage", "Doors")
        let content = garage.sheet(for: doors)
        if RoomGroups.contacts(room: "Garage") == nil {
            #expect(content == .allContacts)
        } else if case .contacts = content {} else {
            Issue.record("Garage doors sheet")
        }
    }

    // MARK: Residents and visits

    @Test func residentsResolveFromTheSignedInUser() {
        for resident in HouseholdResident.allCases {
            #expect(HouseholdResident.forUser(id: resident.haUserId) == resident)
            #expect(HouseholdResident.forUser(id: " \(resident.haUserId.uppercased()) ") == resident)
        }
        #expect(HouseholdResident.forUser(id: nil) == nil)
        #expect(HouseholdResident.forUser(id: "  ") == nil)
        #expect(HouseholdResident.forUser(id: "someone-else") == nil)
    }

    @Test func cardAndItemIdsAreUnique() {
        for page in RoomsConfig.pages {
            #expect(Set(page.allCards.map(\.id)).count == page.allCards.count, "\(page.id)")
        }
        let item = RoomModalItem("Vent 1", "cover.living_room_vent_1_vent", icon: "mdi:air-filter")
        #expect(item.id == "cover.living_room_vent_1_ventVent 1")
    }

    @Test func sheetTilesSendExplicitCommands() async {
        let (room, _, caller, _) = controller("living-room", [:])
        room.send(LightControl.flip("light.living_room", shownOn: true))
        await room.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_off"])
        #expect(caller.calls.first?.data["entity_id"] == "light.living_room")
    }

    @Test func openingARoomFromTheGridCountsAVisit() async {
        let caller = RecordingCaller()
        RoomController.recordVisit(RoomNavigation.item(for: "kitchen")!, caller: caller)
        for _ in 0..<200 where caller.calls.isEmpty { await Task.yield() }
        #expect(caller.calls.map { "\($0.domain).\($0.service)" } == ["script.turn_on"])
        #expect(caller.calls.first?.data["entity_id"] == RoomNavigation.accessIncrementScript)
        #expect(caller.calls.first?.data["variables"]?.contains("kitchen") == true)
    }

    @Test func aFailedVisitCountIsLoggedAndDoesNotSurface() async {
        let caller = RecordingCaller()
        caller.failNext = true
        RoomController.recordVisit(RoomNavigation.item(for: "kitchen")!, caller: caller)
        for _ in 0..<200 where caller.calls.isEmpty { await Task.yield() }
        #expect(caller.calls.count == 1)
    }

    @Test func accessCountsParseLikeTheWeb() {
        #expect(RoomNavigation.accessCount("7") == 7)
        #expect(RoomNavigation.accessCount("7.0") == 7)
        #expect(RoomNavigation.accessCount(" 4 ") == 4)
        #expect(RoomNavigation.accessCount("7.5") == 0)
        #expect(RoomNavigation.accessCount("-1") == 0)
        #expect(RoomNavigation.accessCount("unavailable") == 0)
        #expect(RoomNavigation.accessCount("") == 0)
        #expect(RoomNavigation.accessCount(nil) == 0)
    }

    // MARK: Formatting edge cases

    @Test func compactAndLabelStatesCoverEveryBranch() {
        func e(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes)
        }
        #expect(RoomFormat.compact(e("sensor.a", "unavailable")) == "Unavailable")
        #expect(RoomFormat.compact(e("binary_sensor.contact_front_door", "on")) == "Open")
        #expect(RoomFormat.compact(e("binary_sensor.contact_front_door", "off")) == "Closed")
        #expect(RoomFormat.compact(e("binary_sensor.motion", "on")) == "Active")
        #expect(RoomFormat.compact(e("binary_sensor.motion", "off")) == "Clear")
        #expect(RoomFormat.occupancy(e("binary_sensor.motion", "unavailable")) == "Unavailable")
        #expect(RoomFormat.occupancy(e("binary_sensor.motion", "unknown")) == "Unknown")
        #expect(RoomFormat.occupancy(e("binary_sensor.motion", "paused")) == "Paused")
        #expect(RoomFormat.contact(e("binary_sensor.door", "unavailable")) == "Unavailable")
        #expect(RoomFormat.contact(e("binary_sensor.door", "unknown")) == "Unknown")
        #expect(RoomFormat.contact(e("binary_sensor.door", "ajar")) == "Ajar")
        #expect(RoomFormat.isActive(e("alarm_control_panel.home", "armed_away")))
        #expect(!RoomFormat.isActive(e("alarm_control_panel.home", "disarmed")))
        #expect(RoomFormat.airMetric(e("sensor.pm", "unavailable")) == "Unavailable")
        #expect(RoomFormat.airMetric(e("sensor.pm", " ")) == " ")
        #expect(RoomFormat.temperature(e("sensor.t", "unavailable")) == "Unavailable")
        #expect(RoomFormat.temperature(e("sensor.t", "71.2", ["unit_of_measurement": .string("°F")])) == "71.2°F")
        #expect(RoomFormat.temperature(nil) == "Unavailable")
        #expect(RoomFormat.temperature(e("sensor.t", "21")) == "21")
    }

    @Test func bedWashesFollowEveryClimateAction() {
        let bed = card("master-bedroom", "Stephen's Bed")
        func wash(_ action: String?, state: String = "heat_cool", presence: String? = nil) -> RoomColor? {
            let attributes: [String: JSONValue] = action.map { ["hvac_action": .string($0)] } ?? [:]
            return RoomFormat.background(bed, EntityState(entityId: bed.entityId, state: state, attributes: attributes),
                                         presence: presence.map { EntityState(entityId: "binary_sensor.bed_presence", state: $0) })
        }
        #expect(wash("cooling") == RoomColor(25, 84, 130, opacity: 0.6))
        #expect(wash("idle") == RoomColor(229, 57, 53, opacity: 0.6))
        #expect(wash(nil, state: "off", presence: "on") == RoomColor(0, 150, 136, opacity: 0.6))
        #expect(wash(nil, state: "off", presence: "off") == nil)
        #expect(RoomFormat.background(bed, nil, presence: nil) == nil)
    }
}
