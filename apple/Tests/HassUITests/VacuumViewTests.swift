import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit
#endif

/// Hosted renders of the vacuums page, every sheet tab in each scenario and layout, the area editor, the map canvas
/// and the report, plus the map scene's pure geometry.
@MainActor
struct VacuumViewTests {
    static let phone = CGSize(width: 402, height: 874)
    static let tabletLandscape = CGSize(width: 1210, height: 834)
    static let scenarios: [VacuumFixtures.Scenario] = [.docked, .cleaning, .error, .resumable, .unavailable]

    func image(_ view: some View, size: CGSize, typeSize: DynamicTypeSize = .large) -> CGImage? {
        let renderer = ImageRenderer(content: view.dynamicTypeSize(typeSize).frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    func sheet(_ vacuum: VacuumConfig, _ scenario: VacuumFixtures.Scenario, tab: VacuumTab, window: WindowMetrics? = nil) -> some View {
        let store = VacuumFixtures.store(scenario)
        let controller = VacuumController(vacuum: vacuum, store: store, caller: NullCaller(), scheduler: ManualRevertScheduler())
        return VacuumSheet(controller: controller, loader: VacuumFixtures.loader(vacuum, scenario: scenario), server: nil, catalog: nil,
                           services: VacuumFixtures.services, initialTab: tab, window: window)
    }

    @Test(arguments: Vacuums.all)
    func everyTabRendersInEveryScenarioAndLayout(vacuum: VacuumConfig) {
        for scenario in Self.scenarios {
            for tab in VacuumTab.allCases {
                #expect(image(sheet(vacuum, scenario, tab: tab), size: Self.phone) != nil, "\(vacuum.vacuumMapId) \(scenario) \(tab)")
                #expect(image(sheet(vacuum, scenario, tab: tab, window: WindowMetrics(size: Self.tabletLandscape, isRegularWidth: true)),
                              size: Self.tabletLandscape) != nil, "\(vacuum.vacuumMapId) \(scenario) \(tab) two columns")
            }
        }
    }

    @Test func sheetsRenderAtAccessibilitySizes() {
        for vacuum in Vacuums.all {
            #expect(image(sheet(vacuum, .docked, tab: .controls), size: Self.phone, typeSize: .accessibility5) != nil)
            #expect(image(sheet(vacuum, .docked, tab: .zones), size: Self.phone, typeSize: .accessibility5) != nil)
        }
    }

    @Test func pageRendersSingleAndSplit() {
        for scenario in Self.scenarios {
            let store = VacuumFixtures.store(scenario)
            let page = VacuumsPage(store: store, caller: NullCaller(), scheduler: ManualRevertScheduler()) { _ in EmptyView() }
            #expect(image(page, size: Self.phone) != nil)
            #expect(image(page.environment(\.horizontalSizeClass, .regular), size: Self.tabletLandscape) != nil)
        }
        let empty = VacuumsPage(store: EntityStore(), caller: NullCaller()) { _ in EmptyView() }
        #expect(image(empty, size: Self.phone, typeSize: .accessibility5) != nil)
    }

    @Test func areaEditorReportAndOutcomesRender() throws {
        let store = VacuumFixtures.store()
        let controller = VacuumController(vacuum: Vacuums.mainFloor, store: store, caller: NullCaller(), scheduler: ManualRevertScheduler())
        let mapState = VacuumMapState(vacuum: Vacuums.mainFloor, loader: VacuumFixtures.loader(Vacuums.mainFloor, scenario: .docked))
        #expect(image(NavigationStack { VacuumAreaEditor(controller: controller, mapState: mapState) }, size: Self.phone) != nil)
        controller.areaSelection = .init(x0: 300, x1: 400, y0: 300, y1: 400)
        #expect(image(NavigationStack { VacuumAreaEditor(controller: controller, mapState: mapState) }, size: Self.tabletLandscape) != nil)
        guard case let .typed(contract) = controller.whileAway else { Issue.record("fixture report"); return }
        #expect(image(NavigationStack { VacuumOutcomeDetailView(vacuum: Vacuums.mainFloor, contract: contract) }, size: Self.phone) != nil)
        #expect(image(VacuumCleaningReport(controller: controller, onOpen: { _ in }), size: Self.phone) != nil)
    }

    // MARK: Map scene

    @Test(arguments: Vacuums.all)
    func mapSceneFitsAndFindsRooms(vacuum: VacuumConfig) throws {
        let map = try #require(ValetudoMapFixtures.map(vacuum.vacuumMapId))
        let scene = ValetudoMapScene(map: map, vacuum: vacuum, provenance: .live)
        #expect(scene.cells != nil)
        #expect(scene.aspectRatio > 0.2 && scene.aspectRatio < 5)
        let size = CGSize(width: 360, height: 360 / scene.aspectRatio)
        #expect(image(ValetudoMapCanvas(scene: scene), size: size) != nil)
        let area = MapGeometry.defaultRect(scene.interactionGeometry)
        let orders = vacuum.zones.first.map { [$0.entityId: 1] } ?? [:]
        #expect(image(ValetudoMapCanvas(scene: scene, roomOrders: orders, area: area, showsHandles: true), size: size) != nil)
        // Tapping a room's centroid finds that room.
        let matrix = scene.matrix(size: size, viewport: .initial)
        for room in scene.rooms {
            let point = MapGeometry.framePoint(scene.geometry, matrix: matrix, gridPoint: .init(x: room.centroid.x + 0.5, y: room.centroid.y + 0.5))
            #expect(scene.room(at: CGPoint(x: point.x, y: point.y), size: size)?.entityId == room.entityId, "\(room.title)")
        }
        #expect(scene.room(at: CGPoint(x: -50, y: -50), size: size) == nil)
        let reported = ValetudoMapScene(map: map.reportedOnly(), vacuum: vacuum, provenance: .reported)
        #expect(image(ValetudoMapCanvas(scene: reported), size: size) != nil)
    }

    @Test func mapColorsConvert() {
        #expect(ValetudoMapScene.color(MapRGBA(255, 0, 0)) == Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
    }

    // MARK: Symbols

    /// Every MDI icon the vacuums use maps to an SF Symbol that exists.
    @Test func everyVacuumIconMapsToARealSymbol() {
        var icons: Set<String> = []
        for vacuum in Vacuums.all {
            icons.formUnion(vacuum.zones.map(\.icon))
            icons.formUnion(vacuum.autoCleanDisabledRooms.map(\.icon))
            icons.formUnion(vacuum.consumables.map(\.icon))
        }
        icons.formUnion(Vacuums.autoCleanControls.map(\.icon))
        for scenario in Self.scenarios {
            let store = VacuumFixtures.store(scenario)
            for vacuum in Vacuums.all {
                let controller = VacuumController(vacuum: vacuum, store: store, caller: NullCaller(), scheduler: ManualRevertScheduler())
                controller.services = VacuumFixtures.services
                icons.formUnion((controller.runtimeActions + controller.dockActions + [controller.cleanAction,
                                 controller.areaCleanAction(mapReady: true, selectionAllowed: true)]).map(\.icon))
            }
        }
        for icon in icons.sorted() {
            let symbol = SymbolMap.symbol(for: icon)
            #expect(symbol != "circle", "\(icon) has no mapping")
            #if canImport(AppKit)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(icon) → \(symbol) is not an SF Symbol")
            #endif
        }
    }

    // MARK: Gallery fixtures

    @Test func fixtureEchoMovesTheRobot() throws {
        let store = VacuumFixtures.store()
        let main = Vacuums.mainFloor
        VacuumFixtures.echo("script", main.cleanScript.replacingOccurrences(of: "script.", with: ""), target: nil, store: store)
        #expect(store.value(main.entityId)?.state == "cleaning")
        VacuumFixtures.echo("vacuum", "return_to_base", target: main.entityId, store: store)
        #expect(store.value(main.entityId)?.state == "returning")
        VacuumFixtures.echo("vacuum", "stop", target: main.entityId, store: store)
        #expect(store.value(main.entityId)?.state == "idle")
        let dock = try #require(main.dockControls)
        VacuumFixtures.echo("script", dock.dryScript.replacingOccurrences(of: "script.", with: ""), target: nil, store: store)
        #expect(store.value(dock.dockStatusEntityId)?.state == "drying")
        VacuumFixtures.echo("script", dock.dryScript.replacingOccurrences(of: "script.", with: ""), target: nil, store: store)
        #expect(store.value(dock.dockStatusEntityId)?.state == "idle")
    }
}

/// A scheduler that never fires, so hosted renders leave no timers behind.
final class ManualRevertScheduler: RevertScheduler {
    final class Item: ScheduledWork { func cancel() {} }
    func schedule(after delay: Duration, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork { Item() }
}
