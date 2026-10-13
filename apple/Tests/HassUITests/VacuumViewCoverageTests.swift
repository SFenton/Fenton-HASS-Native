import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit

/// A borderless window that can be key, so SwiftUI keeps its focus targets current.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Hosts a view in an offscreen window and drives it with real mouse events, the way a pointer does.
///
/// SwiftUI registers one `KeyViewProxy` per button, so the buttons are found by position (top to bottom, then left
/// to right) and every test asserts what the tap did, which also proves it hit the control it meant to.
@MainActor
final class UIHost {
    let window: NSWindow
    let hosting: NSHostingView<AnyView>

    init<V: View>(_ view: V, size: CGSize) {
        hosting = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        window = KeyWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        pump()
    }

    /// Removes the content so tasks tied to the view (map polling) are cancelled.
    func close() {
        window.contentView = nil
        window.close()
    }

    func pump(_ seconds: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        hosting.layoutSubtreeIfNeeded()
    }

    /// Frames of the buttons, in the hosting view's coordinates, top to bottom then left to right.
    func frames() -> [CGRect] {
        window.recalculateKeyViewLoop()
        pump(0.15) // lets SwiftUI re-register focus proxies after a state change
        var views: [NSView] = []
        func walk(_ view: NSView) {
            if String(describing: type(of: view)).contains("KeyViewProxy") { views.append(view) }
            view.subviews.forEach(walk)
        }
        walk(hosting)
        return views.map { $0.convert($0.bounds, to: hosting) }.sorted {
            abs($0.minY - $1.minY) > 2 ? $0.minY < $1.minY : $0.minX < $1.minX
        }
    }

    /// Writes a PNG of the view (debugging).
    func snapshot(_ path: String) {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    var buttonCount: Int { frames().count }

    private func windowPoint(_ point: CGPoint) -> CGPoint { hosting.convert(point, to: nil) }

    private func send(_ type: NSEvent.EventType, at point: CGPoint) {
        if let event = NSEvent.mouseEvent(with: type, location: windowPoint(point), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            window.sendEvent(event)
        }
    }

    /// Clicks at a point.
    func click(at point: CGPoint) {
        send(.leftMouseDown, at: point)
        send(.leftMouseUp, at: point)
        pump()
    }

    /// Clicks the nth button.
    func tap(_ index: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let all = frames()
        guard all.indices.contains(index) else { Issue.record("No button \(index) of \(all.count)", sourceLocation: sourceLocation); return }
        // Menus (the 24 pt setting rows) open a modal tracking loop that never returns in a test.
        guard all[index].height > 30 else { Issue.record("Button \(index) is a menu: \(all[index])", sourceLocation: sourceLocation); return }
        click(at: CGPoint(x: all[index].midX, y: all[index].midY))
    }
}

/// Records service calls as `domain.service entity` (plus any data keys) and can be told to fail.
@MainActor
final class CallLog: HassServiceCalling {
    var calls: [String] = []
    var datas: [[String: String]] = []
    var fails = false

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        let entity = (data["entity_id"] as? String) ?? (data["entity_id"] as? [String])?.joined(separator: ",") ?? ""
        calls.append(entity.isEmpty ? "\(domain).\(service)" : "\(domain).\(service) \(entity)")
        datas.append(data.mapValues { "\($0)" })
        if fails { throw URLError(.badServerResponse) }
    }
}

/// A service catalog that answers a fixed set.
@MainActor
final class FixedCatalog: HassServiceCatalog {
    let names: Set<String>
    init(_ names: Set<String>) { self.names = names }
    func serviceNames() async throws -> Set<String> { names }
}

/// One hosted vacuum sheet and what it was built on.
@MainActor
struct SheetRig {
    let host: UIHost
    let controller: VacuumController
    let store: EntityStore
    let log: CallLog
    let loader: ValetudoMapLoader

    static let tall = CGSize(width: 402, height: 1800)

    init(_ vacuum: VacuumConfig = Vacuums.mainFloor, scenario: VacuumFixtures.Scenario = .docked, tab: VacuumTab = .controls,
         size: CGSize = SheetRig.tall, window: WindowMetrics? = nil, services: Set<String>? = VacuumFixtures.services,
         catalog: (any HassServiceCatalog)? = nil, server: HassServer? = nil, loader: ValetudoMapLoader? = nil,
         area: MapGridRect? = nil, edit: (EntityStore) -> Void = { _ in }) {
        let store = VacuumFixtures.store(scenario)
        edit(store)
        let log = CallLog()
        let controller = VacuumController(vacuum: vacuum, store: store, caller: log, scheduler: ManualRevertScheduler())
        controller.areaSelection = area
        let mapLoader = loader ?? VacuumFixtures.loader(vacuum, scenario: scenario)
        host = UIHost(VacuumSheet(controller: controller, loader: mapLoader, server: server, catalog: catalog,
                                  services: services, initialTab: tab, window: window), size: size)
        self.controller = controller
        self.store = store
        self.log = log
        self.loader = mapLoader
        host.pump(0.3) // the sheet loads its service names in a task
    }

    /// Waits for the controller's service calls and lets the view settle.
    func settle() async {
        await controller.waitForCalls()
        host.pump()
    }
}

// MARK: - Helpers

extension EntityStore {
    /// Sets one entity's state (keeping nothing else about it).
    func put(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) {
        apply([EntityState(entityId: id, state: state, attributes: attributes)])
    }
}

@MainActor
enum VacuumRigs {
    /// A rectangle inside the vacuum's drawable map.
    static func area(_ vacuum: VacuumConfig) -> MapGridRect {
        let map = ValetudoMapFixtures.map(vacuum.vacuumMapId)
        return MapGeometry.defaultRect(ValetudoMapScene(map: map, vacuum: vacuum, provenance: .live).interactionGeometry)
    }

    /// The map's frame inside a column `width` wide whose left edge is at `left`, mirroring the views' aspect-fit.
    static func mapRect(_ scene: ValetudoMapScene, left: CGFloat, top: CGFloat, width: CGFloat, maxHeight: CGFloat, minRatio: Double = 0) -> CGRect {
        let ratio = max(scene.aspectRatio, minRatio)
        let height = min(maxHeight, width / ratio)
        let fitted = height * ratio
        return CGRect(x: left + (width - fitted) / 2, y: top, width: fitted, height: height)
    }

    /// A frame point of a grid point on a map drawn into `rect`.
    static func point(_ scene: ValetudoMapScene, in rect: CGRect, viewport: MapViewport = .initial, grid: MapPoint) -> CGPoint {
        let matrix = scene.matrix(size: rect.size, viewport: viewport)
        let p = MapGeometry.framePoint(scene.geometry, matrix: matrix, gridPoint: grid)
        return CGPoint(x: rect.minX + p.x, y: rect.minY + p.y)
    }
}

/// Every test that drives a hosted window runs inside this one serialized suite: they share the app's event queue.
@Suite(.serialized) enum VacuumUI {}

extension VacuumUI {
// MARK: - Controls, rooms, auto-clean, dock and info tabs

@MainActor
struct VacuumSheetInteractionTests {
    let mainId = Vacuums.mainFloor.entityId

    @Test func locateAndCleanSendTheWebServices() async {
        let rig = SheetRig()
        defer { rig.host.close() }
        #expect(rig.host.buttonCount == 9)
        rig.host.tap(0)
        await rig.settle()
        #expect(rig.log.calls == ["vacuum.locate \(mainId)"])
        rig.host.tap(5)
        await rig.settle()
        #expect(rig.log.calls.last == "script.main_floor_vacuum_clean_selected_segments")
        #expect(rig.controller.state == "cleaning", "The tap shows cleaning at once")
        #expect(rig.controller.controlsDisabled, "Commands are held while the clean starts")
    }

    @Test func aRejectedCleanShowsTheErrorAndReenablesCommands() async {
        let rig = SheetRig()
        defer { rig.host.close() }
        rig.log.fails = true
        rig.host.tap(5)
        await rig.settle()
        #expect(rig.controller.cleanError == "Home Assistant rejected the cleaning request.")
        #expect(rig.controller.state == "docked", "The optimistic cleaning state is rolled back")
        #expect(rig.host.buttonCount == 9, "Clean is enabled again")
    }

    @Test func runtimeActionsPerStateSendTheirCommands() async {
        let cleaning = SheetRig(scenario: .cleaning)
        defer { cleaning.host.close() }
        #expect(cleaning.host.buttonCount == 4, "Locate, report, Pause, Stop")
        cleaning.host.tap(2)
        await cleaning.settle()
        #expect(cleaning.log.calls == ["vacuum.pause \(mainId)"])
        #expect(cleaning.controller.state == "paused")
        cleaning.host.tap(3)
        await cleaning.settle()
        #expect(cleaning.log.calls.last == "vacuum.return_to_base \(mainId)", "Stop while cleaning sends the robot home")
        #expect(cleaning.controller.state == "returning")

        let resumable = SheetRig(scenario: .resumable)
        defer { resumable.host.close() }
        #expect(resumable.host.buttonCount == 4, "Locate, report, Resume, Cancel")
        resumable.host.tap(2)
        await resumable.settle()
        #expect(resumable.log.calls == ["vacuum.start \(mainId)"])
        #expect(resumable.controller.state == "cleaning")

        let cancel = SheetRig(scenario: .resumable)
        defer { cancel.host.close() }
        cancel.host.tap(3)
        await cancel.settle()
        #expect(cancel.log.calls == ["vacuum.stop \(mainId)"])
        #expect(cancel.host.buttonCount == 2, "Resume and Cancel are held while the cancel is pending")

        let error = SheetRig(scenario: .error)
        defer { error.host.close() }
        #expect(error.host.buttonCount == 4, "Locate, report, Stop, Dock")
        error.host.tap(2)
        await error.settle()
        #expect(error.log.calls == ["vacuum.stop \(mainId)"], "Stopping from error stops rather than docks")
        error.host.tap(2) // after the stop the robot reads idle, so Dock is the one action left
        await error.settle()
        #expect(error.log.calls.last == "vacuum.return_to_base \(mainId)")
    }

    @Test func anUnavailableRobotOffersOnlyTheReport() {
        let rig = SheetRig(scenario: .unavailable)
        defer { rig.host.close() }
        #expect(rig.host.buttonCount == 1, "No Locate, no commands")
        #expect(!rig.controller.status.primaryAvailable)
        #expect(rig.controller.tabs.contains(.controls))
    }

    @Test func theRoomsTargetOpensTheRoomsTab() async {
        let rig = SheetRig()
        defer { rig.host.close() }
        rig.host.tap(2)
        #expect(rig.host.buttonCount == 13, "Locate, report and the eleven rooms: \(rig.host.frames())")
    }

    @Test func theAreaTargetOpensTheEditorWhenNoRoomsAreSelected() async {
        let rig = SheetRig { store in
            for zone in Vacuums.mainFloor.zones { store.put(zone.entityId, "off") }
        }
        defer { rig.host.close() }
        #expect(rig.controller.selectedZones.isEmpty)
        let before = rig.host.frames()
        rig.host.tap(3)
        #expect(rig.log.calls.isEmpty)
        #expect(rig.host.frames() != before, "The area editor replaced the controls")
    }

    @Test func switchingToAreaWithRoomsSelectedAsksFirst() async {
        let rig = SheetRig()
        defer { rig.host.close() }
        #expect(rig.controller.selectedZones.count == 2)
        rig.host.tap(3)
        #expect(rig.log.calls.isEmpty, "The dialog is pending, nothing was cleared yet")
        #expect(rig.controller.selectedZones.count == 2)
    }

    @Test func areaSetupEditsClearsAndStartsAnAreaClean() async {
        let area = VacuumRigs.area(Vacuums.mainFloor)
        let rig = SheetRig(area: area)
        defer { rig.host.close() }
        // Locate, report, Rooms, Area, Edit Area, Clear Area, passes, Start Area Clean, three power settings.
        #expect(rig.host.buttonCount == 11, "\(rig.host.frames())")
        rig.host.tap(7) // Start Area Clean
        await rig.settle()
        #expect(rig.log.calls.last == "script.main_floor_vacuum_clean_zone")
        let data = rig.log.datas.last ?? [:]
        #expect(Set(data.keys) == ["x_min_cm", "x_max_cm", "y_min_cm", "y_max_cm"])
        #expect(rig.controller.state == "cleaning")
    }

    @Test func clearAreaDiscardsTheSelection() async {
        let rig = SheetRig(area: VacuumRigs.area(Vacuums.mainFloor))
        defer { rig.host.close() }
        rig.host.tap(5) // Clear Area
        #expect(rig.controller.areaSelection == nil)
        #expect(rig.host.buttonCount == 9, "Back to the room setup")
    }

    @Test func areaSetupWithoutTheAreaScriptDisablesStarting() {
        let services = VacuumFixtures.services.subtracting(["script.main_floor_vacuum_clean_zone"])
        let rig = SheetRig(services: services, area: VacuumRigs.area(Vacuums.mainFloor))
        defer { rig.host.close() }
        #expect(!rig.controller.areaServiceReady)
        #expect(rig.host.buttonCount == 10, "Start Area Clean drops out: \(rig.host.frames())")
    }

    @Test func roomButtonsToggleRoomsAndKeepTheirOrder() async {
        let rig = SheetRig(tab: .zones)
        defer { rig.host.close() }
        let zones = Vacuums.mainFloor.zones
        #expect(rig.controller.selectedZones.count == 2, "The fixture starts with two rooms selected")
        #expect(rig.controller.isSelected(zones[0]) && rig.controller.isSelected(zones[2]))
        rig.host.tap(2) // zone 0 (selected): turn off
        await rig.settle()
        #expect(rig.log.calls.first == "input_boolean.turn_off \(zones[0].entityId)")
        #expect(!rig.controller.isSelected(zones[0]))
        rig.host.tap(3) // zone 1 (off): turn on, last in order
        await rig.settle()
        #expect(rig.log.calls.contains("input_boolean.turn_on \(zones[1].entityId)"))
        #expect(rig.controller.isSelected(zones[1]))
        #expect(rig.controller.order(of: zones[1]) == rig.controller.selectedZones.count)
    }

    @Test func turningARoomOnWithAnAreaDrawnWaitsForConfirmation() async {
        let rig = SheetRig(tab: .zones, area: VacuumRigs.area(Vacuums.mainFloor))
        defer { rig.host.close() }
        let zone = Vacuums.mainFloor.zones[1]
        #expect(rig.controller.roomToggleNeedsConfirmation(zone))
        rig.host.tap(3)
        await rig.settle()
        #expect(rig.log.calls.isEmpty, "Nothing is sent until the alert is confirmed")
        #expect(rig.controller.areaSelection != nil)
    }

    @Test func roomsAreLockedWhileTheRobotIsBusy() async {
        let rig = SheetRig(scenario: .cleaning, tab: .zones)
        defer { rig.host.close() }
        #expect(!rig.controller.roomsEditable)
        #expect(!rig.controller.tabs.contains(.zones))
        #expect(rig.host.buttonCount == 4, "The Rooms tab falls back to Controls: Locate, report, Pause, Stop")
    }

    @Test func autoCleanRoomsToggleAndUnavailableOnesAreDisabled() async {
        let rig = SheetRig(tab: .autoClean)
        defer { rig.host.close() }
        let rooms = Vacuums.mainFloor.autoCleanDisabledRooms
        rig.host.tap(2) // first room, included: skip it
        await rig.settle()
        #expect(rig.log.calls == ["switch.turn_on \(rooms[0].entityId)"])
        #expect(rig.controller.isAutoCleanDisabled(rooms[0]))
        rig.host.tap(2) // and back
        await rig.settle()
        #expect(rig.log.calls.last == "switch.turn_off \(rooms[0].entityId)")
        #expect(!rig.controller.isAutoCleanDisabled(rooms[0]))

        let unavailable = SheetRig(tab: .autoClean) { $0.put(rooms[0].entityId, "unavailable") }
        defer { unavailable.host.close() }
        #expect(unavailable.host.buttonCount == rig.host.buttonCount - 1, "The unavailable room can't be tapped")
    }

    @Test func dockControlsRunTheDockScripts() async {
        let music = Vacuums.musicRoom
        let dock = music.dockControls!
        let probe = SheetRig(music, tab: .more)
        defer { probe.host.close() }
        let actions = probe.controller.dockActions
        #expect(actions.map(\.kind) == [.cleanDock, .dryMops, .emptyBin])
        let allEnabled = actions.allSatisfy { !$0.isDisabled }
        #expect(allEnabled, "A docked robot with mop pads and the bridge can run every dock action")
        #expect(probe.host.buttonCount == 4, "Locate plus the three dock actions: \(probe.host.frames())")
        let expected = [dock.cleanScript, dock.dryScript, "button.press \(music.dockButtonEntityId!)"]
        for (index, call) in expected.enumerated() {
            let rig = SheetRig(music, tab: .more)
            defer { rig.host.close() }
            rig.host.tap(1 + index)
            await rig.settle()
            #expect(rig.log.calls == [call])
        }
        let washing = SheetRig(music, tab: .more)
        defer { washing.host.close() }
        washing.host.tap(1)
        await washing.settle()
        #expect(washing.controller.dockActions.first?.kind == .stopDockClean, "The clean action becomes Stop Dock Clean")
        washing.host.tap(1)
        await washing.settle()
        #expect(washing.log.calls == [dock.cleanScript, dock.cleanScript])
    }

    @Test func dockControlsExplainWhatIsMissing() {
        let music = Vacuums.musicRoom
        let missing = SheetRig(music, tab: .more, services: []) { $0.put(music.dockControls!.mopAttachmentEntityId, "off") }
        defer { missing.host.close() }
        #expect(!missing.controller.mopAttached)
        #expect(!missing.controller.dockBridgeAvailable)
        let scripts = missing.controller.dockActions.filter { $0.kind != .emptyBin }
        #expect(scripts.count == 2 && scripts.allSatisfy { $0.isDisabled })
        #expect(missing.host.buttonCount == 2, "Locate and Empty Bin remain: \(missing.host.frames())")
    }

    @Test func dockWashShowsItsStatusWhileTheRunPrepares() async {
        let rig = SheetRig(Vacuums.musicRoom, scenario: .cleaning, tab: .more) {
            $0.put(Vacuums.musicRoom.dockControls!.dockStatusEntityId, "cleaning")
        }
        defer { rig.host.close() }
        #expect(rig.controller.dockPreparationActive)
        #expect(rig.controller.dockActions.isEmpty, "Dock scripts are hidden while the dock washes for the run")
        #expect(rig.host.buttonCount == 1, "Only Locate; the report is gone with the unavailable data: \(rig.host.frames())")
    }

    @Test func infoTabHasNoButtonsBeyondLocateAndReport() {
        let rig = SheetRig(tab: .info)
        defer { rig.host.close() }
        #expect(rig.host.buttonCount == 2)
    }

    @Test func gallerySheetsUseTheirLoaderMapWithoutAServer() {
        let rig = SheetRig()
        defer { rig.host.close() }
        #expect(rig.loader.provenance == .live)
        #expect(rig.loader.map != nil)
    }

    @Test func theCatalogLoadsTheServiceNamesWhenNoneAreSet() async {
        let catalog = FixedCatalog(["script.main_floor_vacuum_clean_zone"])
        let rig = SheetRig(services: nil, catalog: catalog)
        defer { rig.host.close() }
        rig.host.pump(0.5)
        #expect(rig.controller.services == ["script.main_floor_vacuum_clean_zone"])
    }

    @Test func aServerResolvesTheMapCameraPicture() async {
        let server = HassServer(baseURL: URL(string: "https://ha.invalid")!)
        let rig = SheetRig(server: server) {
            $0.put(Vacuums.mainFloor.mapCameraEntityId, "idle", ["entity_picture": .string("/api/camera_proxy/camera.map?token=abc")])
        }
        defer { rig.host.close() }
        rig.host.pump(0.5)
        // The fixture fetch always fails, so the loader keeps showing the last good map.
        #expect(rig.loader.map != nil)
        #expect(rig.loader.provenance == .live)
    }

    @Test func theTabsFallBackToControlsWhenTheModeHidesTheSelectedOne() {
        let rig = SheetRig(scenario: .cleaning, tab: .zones)
        defer { rig.host.close() }
        #expect(!rig.controller.tabs.contains(.zones), "Rooms are hidden while the robot works")
        #expect(rig.host.buttonCount == 4, "The Controls tab shows instead: Locate, report, Pause, Stop")
    }

    @Test func twoColumnLayoutKeepsTheSameControls() async {
        let size = CGSize(width: 1210, height: 834)
        let rig = SheetRig(size: size, window: WindowMetrics(size: size, isRegularWidth: true))
        defer { rig.host.close() }
        #expect(rig.host.buttonCount == 9)
        // Narrow and tall: the setting rows' value menus are narrow too, but only 24 pt tall on the Mac host.
        let locate = rig.host.frames().firstIndex { $0.width < 100 && $0.height > 30 }
        #expect(locate != nil, "Locate keeps its place on the map: \(rig.host.frames())")
        rig.host.tap(locate ?? 0)
        await rig.settle()
        #expect(rig.log.calls == ["vacuum.locate \(mainId)"])
    }
}

// MARK: - Area editor

/// The area editor hosted in a navigation stack, with the map's frame worked out from the layout.
@MainActor
struct EditorRig {
    let host: UIHost
    let controller: VacuumController
    let mapState: VacuumMapState
    let log = CallLog()

    /// Toolbar 44 pt high at the 16 pt page padding, then 16 pt of spacing.
    var mapRect: CGRect? {
        mapState.scene.map { VacuumRigs.mapRect($0, left: 16, top: 76, width: 370, maxHeight: 520, minRatio: 0.6) }
    }

    init(_ vacuum: VacuumConfig = Vacuums.mainFloor, scenario: VacuumFixtures.Scenario = .docked, loader: ValetudoMapLoader? = nil,
         area: MapGridRect? = nil) {
        let store = VacuumFixtures.store(scenario)
        let controller = VacuumController(vacuum: vacuum, store: store, caller: log, scheduler: ManualRevertScheduler())
        controller.areaSelection = area
        let state = VacuumMapState(vacuum: vacuum, loader: loader ?? VacuumFixtures.loader(vacuum, scenario: scenario))
        host = UIHost(NavigationStack { VacuumAreaEditor(controller: controller, mapState: state) },
                      size: CGSize(width: 402, height: 1200))
        self.controller = controller
        mapState = state
    }

    /// A point inside the map at fractions of its width and height.
    func at(_ fx: Double, _ fy: Double) -> CGPoint {
        let r = mapRect ?? .zero
        return CGPoint(x: r.minX + r.width * fx, y: r.minY + r.height * fy)
    }

    func framePoint(_ grid: MapPoint) -> CGPoint {
        VacuumRigs.point(mapState.scene!, in: mapRect ?? .zero, grid: grid)
    }
}

@MainActor
struct VacuumAreaEditorInteractionTests {
    @Test func theToolbarClearsAndRedrawsAnExistingArea() {
        let area = VacuumRigs.area(Vacuums.mainFloor)
        let rig = EditorRig(area: area)
        defer { rig.host.close() }
        #expect(rig.host.buttonCount == 4, "Redraw, Reset View, Clear and Use This Area: \(rig.host.frames())")
        rig.host.tap(2) // Clear
        #expect(rig.controller.areaSelection == nil)
        #expect(rig.host.buttonCount == 2, "Draw and Reset View; Clear and Use are disabled again")

        let redraw = EditorRig(area: area)
        defer { redraw.host.close() }
        redraw.host.tap(0) // Redraw
        #expect(redraw.controller.areaSelection == nil, "Redraw discards the area and waits for a drag")
        #expect(redraw.host.buttonCount == 2)
    }

    @Test func resetViewKeepsTheArea() {
        let area = VacuumRigs.area(Vacuums.mainFloor)
        let rig = EditorRig(area: area)
        defer { rig.host.close() }
        rig.host.tap(1)
        #expect(rig.controller.areaSelection == area)
    }

    @Test func useThisAreaIsEnabledOnlyWithAnArea() {
        let empty = EditorRig()
        defer { empty.host.close() }
        #expect(empty.host.buttonCount == 2)
        let withArea = EditorRig(area: VacuumRigs.area(Vacuums.mainFloor))
        defer { withArea.host.close() }
        #expect(withArea.host.buttonCount == 4)
        withArea.host.tap(3) // Use This Area: nothing to dismiss in a bare stack, and the area stays
        #expect(withArea.controller.areaSelection != nil)
    }

    @Test func anUnconfirmedMapCannotBeDrawnOn() {
        let rig = EditorRig(scenario: .unavailable)
        defer { rig.host.close() }
        #expect(!rig.mapState.isReady, "The reported map is not live")
        #expect(rig.host.buttonCount == 0, "Every tool and Use This Area are disabled")
        #expect(rig.controller.areaSelection == nil)
    }

    @Test func withoutAMapTheEditorSaysSo() {
        let loader = ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) }
        let rig = EditorRig(loader: loader)
        defer { rig.host.close() }
        #expect(rig.mapState.scene == nil)
        #expect(!rig.mapState.isReady)
        #expect(rig.host.buttonCount == 0)
    }

    @Test func anAreaOutsideTheFocusedRoomsIsNotAllowed() throws {
        let music = Vacuums.musicRoom
        let rig = EditorRig(music, area: MapGridRect(x0: 0, x1: 6, y0: 0, y1: 6))
        defer { rig.host.close() }
        let scene = try #require(rig.mapState.scene)
        #expect(scene.focus.mode == .focused)
        #expect(!rig.mapState.allows(rig.controller.areaSelection))
        #expect(rig.mapState.allows(nil))
        #expect(rig.mapState.allows(VacuumRigs.area(music)), "The default rectangle sits inside the focus crop")
    }

    @Test func mapStateRefreshesWhenTheLoaderGetsANewMap() throws {
        let vacuum = Vacuums.mainFloor
        let loader = ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) }
        let state = VacuumMapState(vacuum: vacuum, loader: loader)
        #expect(state.scene == nil)
        loader.show(ValetudoMapFixtures.map(vacuum.vacuumMapId), provenance: .live)
        state.refresh()
        #expect(state.scene != nil && state.isReady)
        let scene = state.scene
        state.refresh()
        #expect(state.scene?.map == scene?.map, "No change, no rebuild")
        loader.show(ValetudoMapFixtures.map(vacuum.vacuumMapId), provenance: .reported)
        state.refresh()
        #expect(!state.isReady, "Reported maps are not drawable")
        #expect(state.scene?.provenance == .reported)
    }
}

// MARK: - Map panel, status and report

@MainActor
struct VacuumMapPanelInteractionTests {
    static let main = Vacuums.mainFloor

    @Test func aMapThatNeverLoadedShowsItsLoadingThenItsUnavailableState() async {
        let loader = ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) }
        let rig = SheetRig(loader: loader)
        defer { rig.host.close() }
        #expect(loader.map == nil && !loader.failed, "Loading while the robot is available")
        await loader.load(from: URL(string: "https://ha.invalid/map")!, live: true)
        rig.host.pump()
        #expect(loader.failed)
        #expect(rig.host.buttonCount >= 2, "Locate stays available on the fallback")
    }

    @Test func anUnavailableRobotWithoutAMapExplainsItself() {
        let loader = ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) }
        let rig = SheetRig(scenario: .unavailable, loader: loader)
        defer { rig.host.close() }
        #expect(!rig.controller.status.primaryAvailable)
        #expect(loader.provenance == .none)
        #expect(rig.host.buttonCount == 1, "Only the report: no Locate while unavailable")
    }

    @Test func aReportedMapShowsItsNotice() {
        let rig = SheetRig(scenario: .unavailable)
        defer { rig.host.close() }
        #expect(rig.loader.provenance == .reported)
        #expect(rig.loader.map != nil)
    }

    @Test func statusNoticesFollowTheErrorSource() {
        let main = Self.main
        let unknown = SheetRig { $0.put(main.errorEntityId, "unavailable") }
        defer { unknown.host.close() }
        #expect(unknown.controller.status.primaryAvailable)
        #expect(unknown.controller.status.currentIssue.status == .unknown)
        let present = SheetRig(scenario: .error)
        defer { present.host.close() }
        #expect(present.controller.status.currentIssue.status == .present)
        #expect(present.controller.status.currentIssue.raw == "Main brush jammed")
        let resumable = SheetRig(scenario: .resumable)
        defer { resumable.host.close() }
        #expect(resumable.controller.status.activeConditions.map(\.code) == ["vacuum.task_resume_pending"])
    }

    // MARK: Report

    func session(_ attributes: [String: JSONValue]) -> (EntityStore) -> Void {
        { $0.put(Self.main.coordinatorSessionEntityId!, "idle", attributes) }
    }

    @Test func aTypedReportOpensItsDetailPage() {
        let rig = SheetRig()
        defer { rig.host.close() }
        guard case .typed = rig.controller.whileAway else { Issue.record("fixture report"); return }
        let before = rig.host.frames()
        rig.host.tap(1)
        #expect(rig.host.frames() != before, "The detail page replaced the sheet's controls")
    }

    @Test func legacyAndProtocolReportsRenderTheirLists() {
        let lines: [String: JSONValue] = ["while_away_cleaned": .array([.string("Kitchen")]), "while_away_issues": .array([.string("Stuck on a rug")])]
        let legacy = SheetRig(edit: session(lines))
        defer { legacy.host.close() }
        #expect(legacy.controller.whileAway == .legacy(cleaned: ["Kitchen"], issues: ["Stuck on a rug"]))
        for (version, complete, kind) in [(1.0, false, VacuumWhileAway.Kind.incomplete), (3.0, true, .incompatible)] {
            var attributes = lines
            attributes["while_away_outcomes"] = .object(["version": .number(version), "complete": .bool(complete)])
            let rig = SheetRig(edit: session(attributes))
            defer { rig.host.close() }
            #expect(rig.controller.whileAway == .protocolNotice(kind, cleaned: ["Kitchen"], issues: ["Stuck on a rug"]))
        }
        var malformed: [String: JSONValue] = [:]
        malformed["while_away_outcomes"] = .string("nonsense")
        let rig = SheetRig(edit: session(malformed))
        defer { rig.host.close() }
        #expect(rig.controller.whileAway == .protocolNotice(.malformed, cleaned: [], issues: []), "No details to disclose")
    }

    @Test func noSessionMeansNoReport() {
        let rig = SheetRig(Vacuums.theaterRoom)
        defer { rig.host.close() }
        #expect(rig.controller.whileAway == .empty)
    }
}
}

// MARK: - Gallery

/// The vacuum gallery page and its fixtures (no hosting needed).
@Suite(.serialized) @MainActor
struct VacuumGalleryTests {
    func image(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 402, height: 874))
        renderer.proposedSize = ProposedViewSize(CGSize(width: 402, height: 874))
        return renderer.cgImage
    }

    func withEnvironment<T>(_ values: [String: String], _ body: () -> T) -> T {
        for (key, value) in values { setenv(key, value, 1) }
        defer { for key in values.keys { unsetenv(key) } }
        return body()
    }

    @Test func theGalleryPageRendersWithAndWithoutTheDebugLine() {
        #expect(image(VacuumGallery()) != nil)
        withEnvironment(["FENTON_GALLERY_CLEAN": "1"]) { #expect(image(VacuumGallery()) != nil) }
    }

    @Test func theGalleryReadsItsScenarioVacuumAndTabFromTheEnvironment() {
        let env = ["FENTON_GALLERY_VACUUM": Vacuums.musicRoom.vacuumMapId, "FENTON_GALLERY_TAB": "more", "FENTON_GALLERY_SCENARIO": "cleaning"]
        withEnvironment(env) { #expect(image(VacuumGallery()) != nil) }
        // Unknown values fall back to the defaults.
        withEnvironment(["FENTON_GALLERY_VACUUM": "nope", "FENTON_GALLERY_TAB": "nope", "FENTON_GALLERY_SCENARIO": "nope"]) {
            #expect(image(VacuumGallery()) != nil)
        }
    }

    @Test func theScenariosSetTheRobotsAndTheirSignals() {
        for vacuum in Vacuums.all {
            let states = Dictionary(uniqueKeysWithValues: VacuumFixtures.states(.docked).map { ($0.entityId, $0.state) })
            #expect(states[vacuum.entityId] == "docked")
        }
        func value(_ scenario: VacuumFixtures.Scenario, _ id: String) -> String? {
            VacuumFixtures.states(scenario).first { $0.entityId == id }?.state
        }
        let main = Vacuums.mainFloor
        #expect(value(.cleaning, main.entityId) == "cleaning")
        #expect(value(.error, main.entityId) == "error")
        #expect(value(.error, main.errorEntityId) == "Main brush jammed")
        #expect(value(.resumable, main.statusFlagEntityId) == "resumable")
        #expect(value(.resumable, main.entityId) == "docked")
        #expect(value(.unavailable, main.entityId) == "unavailable")
        #expect(value(.unavailable, main.batteryEntityId) == "unavailable")
        #expect(value(.docked, main.statusFlagEntityId) == "none")
    }

    @Test func theLoaderShowsTheMockMapAsReportedWhenUnavailable() {
        let live = VacuumFixtures.loader(Vacuums.mainFloor, scenario: .docked)
        #expect(live.provenance == .live && live.map != nil)
        let reported = VacuumFixtures.loader(Vacuums.mainFloor, scenario: .unavailable)
        #expect(reported.provenance == .reported)
    }

    @Test func echoMovesTheRobotLikeHomeAssistant() {
        let store = VacuumFixtures.store()
        let main = Vacuums.mainFloor
        let id = main.entityId
        VacuumFixtures.echo("vacuum", "start", target: id, store: store)
        #expect(store.value(id)?.state == "cleaning")
        VacuumFixtures.echo("vacuum", "pause", target: id, store: store)
        #expect(store.value(id)?.state == "paused")
        VacuumFixtures.echo("vacuum", "stop", target: id, store: store)
        #expect(store.value(id)?.state == "idle", "Stopping a robot that is not docked leaves it idle")
        VacuumFixtures.echo("vacuum", "locate", target: id, store: store)
        #expect(store.value(id)?.state == "idle", "Other services change nothing")
        VacuumFixtures.echo("light", "turn_on", target: id, store: store)
        #expect(store.value(id)?.state == "idle", "Other domains are ignored")
        VacuumFixtures.echo("vacuum", "start", target: nil, store: store)
        #expect(store.value(id)?.state == "idle", "A vacuum call needs a target")
        let area = main.areaCleaning!.script.replacingOccurrences(of: "script.", with: "")
        VacuumFixtures.echo("vacuum", "return_to_base", target: id, store: store)
        #expect(store.value(id)?.state == "returning")
        VacuumFixtures.echo("script", area, target: nil, store: store)
        #expect(store.value(id)?.state == "cleaning", "The area script starts a clean")
    }

    @Test func dockScriptsToggleTheDockStatus() throws {
        let store = VacuumFixtures.store()
        let dock = try #require(Vacuums.musicRoom.dockControls)
        let clean = dock.cleanScript.replacingOccurrences(of: "script.", with: "")
        VacuumFixtures.echo("script", clean, target: nil, store: store)
        #expect(store.value(dock.dockStatusEntityId)?.state == "cleaning")
        VacuumFixtures.echo("script", clean, target: nil, store: store)
        #expect(store.value(dock.dockStatusEntityId)?.state == "idle")
    }
}

// MARK: - Map drawing

/// The map canvas drawing every entity type, material and provenance, compared by pixels.
@MainActor
struct ValetudoMapDrawingTests {
    func pixels(_ view: some View, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
        return data as Data
    }

    /// The vacuum's fixture map with one of every drawable entity, in centimetres around its middle.
    func enriched(_ vacuum: VacuumConfig) -> ValetudoMap {
        var map = ValetudoMapFixtures.map(vacuum.vacuumMapId)
        let b = map.bounds
        let cx = (b.minX + b.maxX) / 2 * map.pixelSize, cy = (b.minY + b.maxY) / 2 * map.pixelSize
        func pts(_ offsets: [(Double, Double)]) -> [Double] { offsets.flatMap { [cx + $0.0, cy + $0.1] } }
        let square = [(-200.0, -200.0), (200, -200), (200, 200), (-200, 200)]
        map.entities += [
            .init(type: "path", points: pts([(-300, 0), (0, 100), (300, 0)])),
            .init(type: "predicted_path", points: pts([(300, 0), (350, 200)])),
            .init(type: "path", points: pts([(0, 0)])),
            .init(type: "no_go_area", points: pts(square)),
            .init(type: "no_mop_area", points: pts(square.map { ($0.0 / 2, $0.1 / 2) })),
            .init(type: "carpet", points: pts(square.map { ($0.0 + 50, $0.1 + 50) })),
            .init(type: "ramp", points: pts(square.map { ($0.0 - 50, $0.1 - 50) })),
            .init(type: "active_zone", points: pts(square.map { ($0.0 / 3, $0.1 / 3) })),
            .init(type: "virtual_wall", points: pts([(-250, -250), (250, 250)])),
            .init(type: "threshold", points: pts([(-250, 250), (250, -250)])),
            .init(type: "curtain", points: pts([(-100, 250), (100, 250)])),
            .init(type: "go_to_target", points: pts([(120, 120)])),
            .init(type: "obstacle", points: pts([(-120, 120)])),
            .init(type: "obstacle", points: [1]),
            .init(type: "unknown_entity", points: pts([(0, 0), (10, 10)])),
        ]
        let materials: [ValetudoMap.Material] = [.tile, .wood, .woodHorizontal, .woodVertical, .carpet, .carpetLow, .carpetHigh, .generic]
        var index = 0
        for layerIndex in map.layers.indices where map.layers[layerIndex].type == "segment" {
            map.layers[layerIndex].material = materials[index % materials.count]
            index += 1
        }
        return map
    }

    @Test(arguments: Vacuums.all)
    func entitiesAndMaterialsChangeTheDrawing(vacuum: VacuumConfig) throws {
        let plain = ValetudoMapScene(map: ValetudoMapFixtures.map(vacuum.vacuumMapId), vacuum: vacuum, provenance: .live)
        let rich = ValetudoMapScene(map: enriched(vacuum), vacuum: vacuum, provenance: .live)
        #expect(rich.cells != nil)
        let size = CGSize(width: 360, height: 360 / rich.aspectRatio)
        let before = try #require(pixels(ValetudoMapCanvas(scene: plain), size: size))
        let after = try #require(pixels(ValetudoMapCanvas(scene: rich), size: size))
        #expect(before != after, "Entities and material accents are drawn")
        // The same map reported from memory keeps only the robot and the dock.
        let reported = ValetudoMapScene(map: enriched(vacuum).reportedOnly(), vacuum: vacuum, provenance: .reported)
        let reportedPixels = try #require(pixels(ValetudoMapCanvas(scene: reported), size: size))
        #expect(reportedPixels != after)
        // Zoomed and panned, with an area and numbered rooms, it still draws.
        let area = MapGeometry.defaultRect(rich.interactionGeometry)
        let zoomed = ValetudoMapCanvas(scene: rich, viewport: MapViewport(panX: 10, panY: -10, zoom: 3),
                                       roomOrders: Dictionary(uniqueKeysWithValues: rich.rooms.enumerated().map { ($1.entityId, $0 + 1) }),
                                       area: area, showsHandles: true)
        #expect(try #require(pixels(zoomed, size: size)) != after)
    }

    @Test func aMapTooLargeToRasteriseHasNoCellImageButStillHasAFrame() {
        let vacuum = Vacuums.mainFloor
        let base = ValetudoMapFixtures.map(vacuum.vacuumMapId)
        let huge = ValetudoMap(layers: [.init(type: "floor", pixels: [0, 0, 6000, 6000])], entities: [], pixelSize: base.pixelSize,
                               size: (6001, 6001))
        let scene = ValetudoMapScene(map: huge, vacuum: vacuum, provenance: .live)
        #expect(scene.cells == nil, "More than 16 million cells is not rasterised")
        #expect(scene.aspectRatio > 0)
    }
}
#endif
