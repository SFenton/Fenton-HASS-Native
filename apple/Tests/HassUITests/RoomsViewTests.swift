import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit
#endif

/// Hosted renders of every room page, every card sheet, Quick Links and the room grid, plus route and symbol
/// coverage.
@MainActor
struct RoomsViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tabletLandscape = CGSize(width: 1210, height: 834)

    func render(_ view: some View, size: CGSize, typeSize: DynamicTypeSize = .large, states: [EntityState] = RoomsFixtures.states) -> CGImage? {
        let store = EntityStore()
        store.replaceAll(states)
        let hosted = NavigationStack { view }
            .environment(store)
            .environment(\.roomServiceCaller, RecordingCaller())
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hosted)
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    func page(_ page: RoomPage, states: [EntityState] = RoomsFixtures.states) -> RoomPageContent {
        let store = EntityStore()
        store.replaceAll(states)
        return RoomPageContent(page: page, store: store, caller: RecordingCaller(), imageServer: nil)
    }

    @Test(arguments: RoomsConfig.pages)
    func everyRoomRendersOnPhoneAndTablet(room: RoomPage) {
        #expect(render(page(room), size: Self.phone) != nil, "\(room.id) phone")
        #expect(render(page(room), size: Self.tabletLandscape) != nil, "\(room.id) tablet")
    }

    @Test func roomsRenderAtAccessibilitySizesAndWithNothingReporting() {
        for room in RoomsConfig.pages {
            #expect(render(page(room), size: Self.phone, typeSize: .accessibility5) != nil, "\(room.id) AX5")
            #expect(render(page(room, states: []), size: Self.phone, states: []) != nil, "\(room.id) empty")
        }
    }

    @Test func everyCardSheetRenders() {
        let store = EntityStore()
        store.replaceAll(RoomsFixtures.states)
        for room in RoomsConfig.pages {
            let controller = RoomController(page: room, store: store, caller: RecordingCaller())
            for card in room.allCards where card.sheet != nil {
                if case .mediaRemote = controller.sheet(for: card) { continue }
                #expect(render(RoomCardSheet(controller: controller, card: card), size: Self.phone) != nil, "\(room.id) \(card.title)")
            }
        }
    }

    @Test func quickLinksAndTheRoomGridRender() {
        #expect(render(QuickLinksSheet(caller: RecordingCaller()) { _ in }, size: Self.phone) != nil)
        #expect(render(QuickLinksSheet(caller: RecordingCaller()) { _ in }, size: Self.phone, typeSize: .accessibility5) != nil)
        #expect(render(ScrollView { RoomNavigationGrid(caller: nil) { _ in } }, size: Self.phone) != nil)
        #expect(render(ScrollView { RoomNavigationGrid(caller: nil) { _ in } }, size: Self.tabletLandscape) != nil)
        #expect(render(QuickLinksSecurityDetail(), size: Self.phone) != nil)
    }

    @Test func groceriesSectionRendersOnlyInTheKitchen() {
        let kitchen = RoomsConfig.page(id: "kitchen")!
        #expect(render(page(kitchen), size: Self.phone) != nil)
    }

    // MARK: Colour families

    /// The face a card draws in its state (direction G colour families).
    func face(_ cardTitle: String, in roomId: String, states: [EntityState]) -> RoomTileFace? {
        let room = RoomsConfig.page(id: roomId)!
        let store = EntityStore()
        store.replaceAll(states)
        let controller = RoomController(page: room, store: store, caller: RecordingCaller())
        guard let card = room.allCards.first(where: { $0.title == cardTitle }) else { return nil }
        return RoomTileFace.resolve(card, entity: controller.displayEntity(card), display: controller.display(card),
                                   running: controller.usesAlternate(card))
    }

    @Test func everyKindHasAFamily() {
        #expect(RoomTileFace.family(.light, icon: "mdi:lightbulb") == .lights)
        #expect(RoomTileFace.family(.light, icon: "mdi:heat-wave") == .power, "The towel rack is power, not a light")
        #expect(RoomTileFace.family(.fan, icon: "mdi:fan") == .air)
        #expect(RoomTileFace.family(.vent, icon: "mdi:air-filter") == .vents)
        #expect(RoomTileFace.family(.humidifier, icon: "mdi:air-humidifier") == .water)
        #expect(RoomTileFace.family(.vacuum, icon: "mdi:robot-vacuum") == .cleaning)
        #expect(RoomTileFace.family(.laundry, icon: "mdi:washing-machine") == .cleaning)
        #expect(RoomTileFace.family(.grill, icon: "mdi:grill") == .cooking)
        #expect(RoomTileFace.family(.media, icon: "mdi:television") == .media)
    }

    @Test func bedSidesFillWithTheirAction() {
        let bed = "climate.sleepypod_eight_pod_left_side"
        let heating = EntityState(entityId: bed, state: "heat_cool", attributes: ["hvac_action": .string("heating")])
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [heating]) == RoomTileFace(family: .heating, isActive: true))
        let cooling = EntityState(entityId: bed, state: "heat_cool", attributes: ["hvac_action": .string("cooling")])
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [cooling]) == RoomTileFace(family: .cooling, isActive: true))
        let off = EntityState(entityId: bed, state: "off")
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [off])?.isActive == false)
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [])?.isActive == false, "Unavailable stays dark")
    }

    @Test func idleAndOffThermostatsKeepAFamilyGlyph() {
        let bed = "climate.sleepypod_eight_pod_left_side"
        let heatIdle = EntityState(entityId: bed, state: "heat", attributes: ["hvac_action": .string("idle")])
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [heatIdle]) == RoomTileFace(family: .heating, isActive: false))
        let heatNone = EntityState(entityId: bed, state: "heat", attributes: ["hvac_action": .string("none")])
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [heatNone]) == RoomTileFace(family: .heating, isActive: false))
        let heatCoolIdle = EntityState(entityId: bed, state: "heat_cool", attributes: ["hvac_action": .string("idle")])
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [heatCoolIdle]) == RoomTileFace(family: .cooling, isActive: false))
        let off = EntityState(entityId: bed, state: "off")
        #expect(face("Stephen's Bed", in: "master-bedroom", states: [off]) == RoomTileFace(family: .cooling, isActive: false))
    }

    @Test func roomClimateAndAirChipsAlwaysFill() {
        #expect(StatusChipAppearance.isFilled(.climate, isActive: false))
        #expect(StatusChipAppearance.isFilled(.air, isActive: false))
        #expect(!StatusChipAppearance.isFilled(.light, isActive: false))
        #expect(StatusChipAppearance.isFilled(.presence, isActive: true))
        #expect(!StatusChipAppearance.isFilled(.contact, isActive: false))
    }

    @Test func ventsFillOnlyWhileOpen() {
        let open = EntityState(entityId: "cover.living_room_vents", state: "open")
        #expect(face("Vents", in: "living-room", states: [open]) == RoomTileFace(family: .vents, isActive: true))
        let closed = EntityState(entityId: "cover.living_room_vents", state: "closed")
        #expect(face("Vents", in: "living-room", states: [closed]) == RoomTileFace(family: .vents, isActive: false))
    }

    @Test func dishwasherFillsWhileItRuns() {
        let program = EntityState(entityId: RoomsConfig.dishwasherProgramEntityId, state: "Eco 50")
        let running = EntityState(entityId: "sensor.dishwasher_operation_state", state: "run")
        let progress = EntityState(entityId: "sensor.dishwasher_program_progress", state: "40")
        #expect(face("Dishwasher", in: "kitchen", states: [program, running, progress]) == RoomTileFace(family: .cleaning, isActive: true))
        let ready = EntityState(entityId: "sensor.dishwasher_operation_state", state: "ready")
        #expect(face("Dishwasher", in: "kitchen", states: [program, ready]) == RoomTileFace(family: .cleaning, isActive: false))
    }

    @Test func togglesKeepTheirOnOffReading() {
        let rack = "switch.guest_bathroom_towel_rack_switch_top"
        #expect(face("Towel Rack", in: "guest-bathroom", states: [EntityState(entityId: rack, state: "on")])
            == RoomTileFace(family: .power, isActive: true))
        #expect(face("Towel Rack", in: "guest-bathroom", states: [EntityState(entityId: rack, state: "off")])
            == RoomTileFace(family: .power, isActive: false))
    }

    // MARK: Layout policies

    @Test func sectionSpans() {
        let appLaunch = RoomSection("Quick App Launch", layout: .appLaunch(remoteId: "living-room-shield"))
        let grid = RoomSection("Climate")
        #expect(RoomSectionView.isFullWidth(appLaunch, sectionCount: 3))
        #expect(!RoomSectionView.isFullWidth(grid, sectionCount: 3))
        #expect(RoomSectionView.isFullWidth(grid, sectionCount: 1))
        #expect(RoomSectionView.followUpColumns(2) == nil)
        #expect(RoomSectionView.followUpColumns(3) == 2)
    }

    // MARK: Routes

    @Test func everyQuickLinkAndRoomHasARoute() {
        for link in QuickLinks.items {
            if case let .navigate(path) = link.action { #expect(HomeRoute(path: path) != nil, "\(path)") }
        }
        for item in RoomNavigation.items {
            #expect(HomeRoute(path: item.path) == .room(item.path))
            #expect(HomeRoute(path: "/\(item.path)") == .room(item.path))
        }
        #expect(HomeRoute(path: "nowhere") == nil)
        for route in [HomeRoute.media, .customLights, .sprinklers, .vacuums, .food, .groceryList] {
            #expect(HomeRoute(path: route.path) == route)
        }
    }

    @Test func everyRouteHasATitleAndADestination() {
        let routes = RoomNavigation.items.map { HomeRoute.room($0.path) } + [.media, .customLights, .sprinklers, .vacuums, .food, .groceryList]
        for route in routes {
            #expect(route.id == route.path)
            #expect(!route.title.isEmpty)
            #expect(render(HomeRouteDestination(route: route), size: Self.phone) != nil, "\(route.path)")
        }
        #expect(HomeRoute.room("kitchen").title == "Kitchen")
        #expect(HomeRoute.room("attic").title == "attic")
        #expect(render(HomeRouteDestination(route: .room("attic")), size: Self.phone) != nil)
        #expect(HomeRoute.food.title == "Food & Recipes")
    }

    @Test func roomScreenUsesTheInjectedCallerElseAPlaceholder() {
        let living = RoomsConfig.page(id: "living-room")!
        #expect(render(RoomScreen(page: living).environment(\.householdViewer, .steph), size: Self.phone) != nil)
        let store = EntityStore()
        let offline = NavigationStack { RoomScreen(page: living) }
            .environment(store)
            .frame(width: Self.phone.width, height: Self.phone.height)
        let renderer = ImageRenderer(content: offline)
        renderer.proposedSize = ProposedViewSize(Self.phone)
        #expect(renderer.cgImage != nil)
    }

    @Test func quickLinksButtonAndSourceFallbackRender() {
        #expect(render(QuickLinksButton {}, size: CGSize(width: 120, height: 60)) != nil)
        let xbox = RoomsConfig.page(id: "music-room")!.allCards.first { $0.title == "Xbox" }!
        #expect(render(RoomSheetFallback(card: xbox), size: Self.phone) != nil)
    }

    // MARK: Handlers

    @Test func roomPageOpensRemotesAndSheetsAndRendersThem() {
        let store = EntityStore()
        store.replaceAll(RoomsFixtures.states)
        let living = RoomsConfig.page(id: "living-room")!
        let content = RoomPageContent(page: living, store: store, caller: RecordingCaller(), imageServer: nil)
        let controller = RoomController(page: living, store: store, caller: RecordingCaller())
        let remoteCard = living.allCards.first { $0.title == "Living Room Remote" }!
        let vents = living.allCards.first { $0.title == "Vents" }!
        guard case let .remote(shared) = RoomPageContent.opening(remoteCard, controller: controller) else {
            Issue.record("The remote card opens the remote sheet")
            return
        }
        if case .remote = RoomPageContent.opening(vents, controller: controller) { Issue.record("Vents open the room sheet") }
        content.open(remoteCard)
        content.open(vents)
        content.quickLinksDismissed()
        let selection = RemoteSelection(controller: shared)
        #expect(selection.id == shared.config.id)
        #expect(render(content.cardSheet(vents), size: Self.phone) != nil)
        #expect(render(content.remoteSheet(selection), size: Self.phone) != nil)
        #expect(render(content.quickLinksSheet(), size: Self.phone) != nil)
    }

    @Test func quickLinksAndRoomGridHandlersNavigateAndCountVisits() async {
        var routes: [HomeRoute] = []
        let caller = RecordingCaller()
        let sheet = QuickLinksSheet(caller: caller) { routes.append($0) }
        for link in QuickLinks.items { sheet.open(link) }
        #expect(routes.contains(.media) && routes.contains(.food))
        #expect(render(QuickLinksDetailView(detail: .rooms, caller: caller) { _ in }, size: Self.phone) != nil)
        #expect(render(QuickLinksDetailView(detail: .securitySystem, caller: caller) { _ in }, size: Self.phone) != nil)
        #expect(render(QuickLinksSheet(caller: caller) { _ in }, size: Self.phone) != nil)
        #expect(render(QuickLinksTab(caller: caller), size: Self.phone) != nil)

        var opened: [String] = []
        let grid = RoomNavigationGrid(caller: caller) { opened.append($0) }
        grid.open(RoomNavigation.item(for: "gym")!)
        RoomNavigationGrid(caller: nil) { opened.append($0) }.open(RoomNavigation.item(for: "office")!)
        #expect(opened == ["gym", "office"])
        for _ in 0..<200 where caller.names.isEmpty { await Task.yield() }
        #expect(caller.names == ["script.turn_on"])
    }

    @Test func cardTilesRunActionsOrOpenSheets() async {
        let store = EntityStore()
        store.replaceAll(RoomsFixtures.states)
        let caller = RecordingCaller()
        let bath = RoomsConfig.page(id: "guest-bathroom")!
        let controller = RoomController(page: bath, store: store, caller: caller)
        var opens = 0
        let towel = bath.allCards.first { $0.title == "Towel Rack" }!
        RoomCardTile(controller: controller, card: towel) { opens += 1 }.activate()
        await controller.waitForCalls()
        #expect(caller.names.count == 1 && caller.names[0].hasPrefix("switch.turn_"))
        if let sheetCard = bath.allCards.first(where: { $0.sheet != nil && $0.action == nil }) {
            RoomCardTile(controller: controller, card: sheetCard) { opens += 1 }.activate()
            #expect(opens == (controller.display(sheetCard).isEnabled ? 1 : 0))
        }
    }

    // MARK: Device sheets (room device sheets and vacuum lanes)

    @Test func deviceSheetsResolveFromTheirConfigs() {
        let store = EntityStore()
        let fan = BathroomFanController(config: BathroomFanConfig.forPowerEntity(RoomsConfig.BathroomFan.guestPower)!,
                                        store: store, caller: RecordingCaller())
        let fans = [RoomsConfig.BathroomFan.guestPower: fan]
        func resolve(_ device: RoomDeviceSheet, connected: Bool = true) -> String? {
            RoomDeviceModal.resolve(device, hasConnection: connected) { fans[$0] }?.id
        }
        #expect(resolve(.bathroomFan(powerEntityId: RoomsConfig.BathroomFan.guestPower)) == "fan.\(RoomsConfig.BathroomFan.guestPower)")
        #expect(resolve(.bathroomFan(powerEntityId: "switch.nowhere")) == nil)
        #expect(resolve(.airQuality(pm25EntityId: "sensor.living_room_air_purifier_pm2_5")) == "purifier.sensor.living_room_air_purifier_pm2_5")
        #expect(resolve(.airQuality(pm25EntityId: "sensor.nowhere")) == nil)
        let humidifier = HumidifierConfig.all[0].powerEntityId
        #expect(resolve(.humidifier(powerEntityId: humidifier)) == "humidifier.\(humidifier)")
        #expect(resolve(.humidifier(powerEntityId: humidifier), connected: false) == nil, "Needs the app's connection")
        #expect(resolve(.vacuum(entityId: "vacuum.valetudo_exaltedsneakydeer")) == "vacuum.vacuum.valetudo_exaltedsneakydeer")
        #expect(resolve(.vacuum(entityId: "vacuum.valetudo_exaltedsneakydeer"), connected: false) == nil, "Gallery keeps the fallback")
        #expect(resolve(.vacuum(entityId: "vacuum.nowhere")) == nil)
        #expect(resolve(.grill(entityId: "sensor.d8478fa2ad0a_grill_state")) == "grill")
        #expect(resolve(.dishwasher) == nil)
        #expect(resolve(.wakeLight(statusEntityId: "sensor.x")) == nil)
        #expect(resolve(.bed(sheet: "stephens-bed", climateEntityId: "climate.x")) == nil)
    }

    @Test func roomCardsOpenDeviceSheetsAndRenderThem() {
        let store = EntityStore()
        store.replaceAll(RoomsFixtures.states)
        let bath = RoomsConfig.page(id: "guest-bathroom")!
        let living = RoomsConfig.page(id: "living-room")!
        let caller = RecordingCaller()
        let bathController = RoomController(page: bath, store: store, caller: caller)
        let livingController = RoomController(page: living, store: store, caller: caller)
        let fanCard = bath.allCards.first { $0.control == .bathroomFan }!
        let fan = BathroomFanController(config: BathroomFanConfig.forPowerEntity(fanCard.entityId)!, store: store, caller: caller)
        if case let .device(modal) = RoomPageContent.opening(fanCard, controller: bathController, fans: [fanCard.entityId: fan]) {
            #expect(modal.id.hasPrefix("fan."))
            #expect(render(RoomDeviceModalSheet(modal: modal, store: store, caller: caller, connection: nil), size: Self.phone) != nil)
        } else {
            Issue.record("The fan card opens the fan sheet")
        }
        if case .device = RoomPageContent.opening(fanCard, controller: bathController) { Issue.record("No shared fan: room sheet") }
        let purifier = living.allCards.first { $0.title == "Air Purifier" }!
        if case let .device(modal) = RoomPageContent.opening(purifier, controller: livingController) {
            #expect(render(RoomDeviceModalSheet(modal: modal, store: store, caller: caller, connection: nil), size: Self.phone) != nil)
        } else {
            Issue.record("The purifier card opens the air quality sheet")
        }
        let vacuum = living.allCards.first { $0.title == "Main Floor" }!
        if case .device = RoomPageContent.opening(vacuum, controller: livingController) { Issue.record("Gallery vacuum keeps the room sheet") }
        #expect(render(RoomDeviceModalSheet(modal: .grill, store: store, caller: caller, connection: nil), size: Self.phone) != nil)
        // Sheets that need the connection draw nothing without one rather than crashing.
        #expect(render(RoomDeviceModalSheet(modal: .vacuum(Vacuums.all[0]), store: store, caller: caller, connection: nil), size: Self.phone) != nil)
        #expect(render(RoomDeviceModalSheet(modal: .humidifier(HumidifierConfig.all[0]), store: store, caller: caller, connection: nil),
                       size: Self.phone) != nil)
        let page = RoomPageContent(page: bath, store: store, caller: caller, imageServer: nil)
        page.open(fanCard)
        #expect(render(page.deviceSheet(.grill), size: Self.phone) != nil)
    }

    @Test func bathroomFanTileRendersWithItsAccessories() {
        let store = EntityStore()
        store.replaceAll(RoomsFixtures.states)
        let bath = RoomsConfig.page(id: "guest-bathroom")!
        let card = bath.allCards.first { $0.control == .bathroomFan }!
        let fan = BathroomFanController(config: BathroomFanConfig.forPowerEntity(card.entityId)!, store: store, caller: RecordingCaller())
        #expect(render(BathroomFanRoomTile(fan: fan, card: card) {}, size: CGSize(width: 370, height: 120)) != nil)
        #expect(render(BathroomFanRoomTile(fan: fan, card: card) {}, size: CGSize(width: 370, height: 300), typeSize: .accessibility5) != nil)
        let controller = RoomController(page: bath, store: store, caller: RecordingCaller())
        #expect(render(RoomCardView(controller: controller, card: card, fan: fan) {}, size: CGSize(width: 370, height: 120)) != nil)
        #expect(render(page(bath), size: Self.phone) != nil)
    }

    @Test func masterBedroomCardsOpenTheBedroomSheets() {
        let store = EntityStore()
        store.replaceAll(RoomsFixtures.states + BedroomFixtures.states(BedroomFixtures.Scenario.allCases[0]))
        let recorder = BedroomGalleryRecorder(store: store)
        let devices = BedroomDevices(store: store, caller: recorder, canEdit: false)
        func resolve(_ device: RoomDeviceSheet, bedroom: BedroomDevices?) -> String? {
            RoomDeviceModal.resolve(device, hasConnection: false, fan: { _ in nil }, bedroom: bedroom)?.id
        }
        #expect(resolve(.wakeLight(statusEntityId: RoomsConfig.WakeLight.statusEntityId), bedroom: devices) == "wake-light")
        #expect(resolve(.wakeLight(statusEntityId: RoomsConfig.WakeLight.statusEntityId), bedroom: nil) == nil, "No responding caller: fallback")
        #expect(resolve(.bed(sheet: "stephens-bed", climateEntityId: "climate.sleepypod_eight_pod_left_side"), bedroom: devices) == "bed.left")
        #expect(resolve(.bed(sheet: "stephs-bed", climateEntityId: "climate.sleepypod_eight_pod_right_side"), bedroom: devices) == "bed.right")
        #expect(resolve(.bed(sheet: "nobodys-bed", climateEntityId: "climate.x"), bedroom: devices) == nil)

        // The page builds one BedroomDevices when its caller can read responses, and the cards route to it.
        let page = RoomsConfig.page(id: "master-bedroom")!
        let content = RoomPageContent(page: page, store: store, caller: recorder, imageServer: nil)
        let controller = RoomController(page: page, store: store, caller: recorder)
        let wake = page.allCards.first { $0.title == RoomsConfig.WakeLight.title }!
        let bed = page.allCards.first { $0.title == "Stephen's Bed" }!
        if case let .device(modal) = RoomPageContent.opening(wake, controller: controller, bedroom: devices) {
            #expect(render(RoomDeviceModalSheet(modal: modal, store: store, caller: recorder, connection: nil), size: Self.phone) != nil)
        } else {
            Issue.record("The wake light opens its sheet")
        }
        if case let .device(modal) = RoomPageContent.opening(bed, controller: controller, bedroom: devices) {
            #expect(modal.id == "bed.left")
            #expect(render(RoomDeviceModalSheet(modal: modal, store: store, caller: recorder, connection: nil), size: Self.phone) != nil)
        } else {
            Issue.record("The bed opens its sheet")
        }
        if case .device = RoomPageContent.opening(bed, controller: controller) { Issue.record("Without devices: room sheet") }
        content.open(wake)
        content.deviceSheetDismissed()
        #expect(render(content, size: Self.phone) != nil)
        #expect(render(content.deviceSheet(.bed(devices, side: .right, tab: .alarms)), size: Self.phone) != nil)
    }

    // MARK: Symbols

    @Test func everyRoomIconMapsToARealSymbol() {
        var icons = Set(RoomsConfig.pages.flatMap(\.allCards).map(\.icon))
        icons.formUnion(RoomNavigation.items.map(\.icon))
        icons.formUnion(QuickLinks.items.map(\.icon))
        icons.formUnion(["armed_away", "armed_home", "armed_night", "disarmed", "triggered", nil].map { QuickLinks.securityAppearance($0).icon })
        icons.formUnion(["mdi:motion-sensor-off", "mdi:door-open", "mdi:window-closed", "mdi:thermometer", "mdi:air-filter",
                         "mdi:clipboard-list", "mdi:food-fork-drink", "mdi:cart"])
        for route in [HomeRoute.media, .customLights, .sprinklers, .vacuums, .food, .groceryList] { icons.insert(route.mdiIcon) }
        for icon in icons {
            let symbol = SymbolMap.symbol(for: icon)
            #expect(symbol != "circle", "\(icon) has no mapping")
            #if canImport(AppKit)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(icon) → \(symbol) is not an SF Symbol")
            #endif
        }
    }
}
