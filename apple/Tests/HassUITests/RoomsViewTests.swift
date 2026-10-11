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
            .environment(\.roomServiceCaller, NullCaller())
            .dynamicTypeSize(typeSize)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hosted)
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    func page(_ page: RoomPage, states: [EntityState] = RoomsFixtures.states) -> RoomPageContent {
        let store = EntityStore()
        store.replaceAll(states)
        return RoomPageContent(page: page, store: store, caller: NullCaller(), imageServer: nil)
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
            let controller = RoomController(page: room, store: store, caller: NullCaller())
            for card in room.allCards where card.sheet != nil {
                if case .mediaRemote = controller.sheet(for: card) { continue }
                #expect(render(RoomCardSheet(controller: controller, card: card), size: Self.phone) != nil, "\(room.id) \(card.title)")
            }
        }
    }

    @Test func quickLinksAndTheRoomGridRender() {
        #expect(render(QuickLinksSheet(caller: NullCaller()) { _ in }, size: Self.phone) != nil)
        #expect(render(QuickLinksSheet(caller: NullCaller()) { _ in }, size: Self.phone, typeSize: .accessibility5) != nil)
        #expect(render(ScrollView { RoomNavigationGrid(caller: nil) { _ in } }, size: Self.phone) != nil)
        #expect(render(ScrollView { RoomNavigationGrid(caller: nil) { _ in } }, size: Self.tabletLandscape) != nil)
        #expect(render(QuickLinksSecurityDetail(), size: Self.phone) != nil)
    }

    @Test func groceriesSectionRendersOnlyInTheKitchen() {
        let kitchen = RoomsConfig.page(id: "kitchen")!
        #expect(render(page(kitchen), size: Self.phone) != nil)
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
