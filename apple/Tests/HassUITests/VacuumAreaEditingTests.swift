import CoreGraphics
import Foundation
import HassCore
@testable import HassUI
import Testing

/// The area editor's map math on a real scene: hit-testing, corner reach, drag routing and pinch zoom.
struct VacuumAreaEditingTests {
    let vacuum = Vacuums.mainFloor
    var scene: ValetudoMapScene { ValetudoMapScene(map: ValetudoMapFixtures.map(vacuum.vacuumMapId), vacuum: vacuum, provenance: .live) }
    let size = CGSize(width: 360, height: 520)

    private func frame(_ grid: MapPoint, _ scene: ValetudoMapScene, viewport: MapViewport = .initial) -> CGPoint {
        let p = MapGeometry.framePoint(scene.geometry, matrix: scene.matrix(size: size, viewport: viewport), gridPoint: grid)
        return CGPoint(x: p.x, y: p.y)
    }

    @Test func minimumSizeIsTheConfiguredCentimetresInCells() {
        let scene = scene
        let expected = ((vacuum.areaCleaning?.minimumSizeCm ?? 25) / scene.interactionGeometry.pixelSize).rounded(.up)
        #expect(scene.minimumAreaCells(vacuum) == expected)
        var noArea = vacuum
        noArea.areaCleaning = nil
        #expect(scene.minimumAreaCells(noArea) == (25 / scene.interactionGeometry.pixelSize).rounded(.up), "25 cm by default")
    }

    @Test func gridPointsRoundTripThroughTheFrame() {
        let scene = scene
        let g = scene.interactionGeometry
        let grid = MapPoint(x: (g.minGridX + g.maxGridX) / 2, y: (g.minGridY + g.maxGridY) / 2)
        for viewport in [MapViewport.initial, .init(panX: 20, panY: -15, zoom: 2.5)] {
            let back = scene.gridPoint(frame(grid, scene, viewport: viewport), size: size, viewport: viewport)
            #expect(abs(back.x - grid.x) < 1e-6 && abs(back.y - grid.y) < 1e-6)
        }
    }

    @Test func cornersAreReachableWithin22Points() {
        let scene = scene
        let rect = MapAreaEdit.voiceOverStart(scene.interactionGeometry, minimum: 5)
        for corner in MapGridRect.Corner.allCases {
            let p = frame(rect.point(corner), scene)
            #expect(scene.corner(near: p, of: rect, size: size, viewport: .initial) == corner)
            #expect(scene.corner(near: CGPoint(x: p.x + 21, y: p.y), of: rect, size: size, viewport: .initial) != nil)
        }
        let centre = frame(.init(x: (rect.x0 + rect.x1) / 2, y: (rect.y0 + rect.y1) / 2), scene)
        #expect(scene.corner(near: centre, of: rect, size: size, viewport: .init(zoom: 4)) == nil, "zoomed in, the centre is far from every corner")
    }

    @Test func dragsPickTheirJobOnceAndKeepIt() {
        let scene = scene
        let rect = MapAreaEdit.voiceOverStart(scene.interactionGeometry, minimum: 5)
        let a = frame(rect.point(.a), scene)
        // Targets are given in grid cells: the Main Floor map is rotated, so frame directions differ.
        let outward = frame(.init(x: rect.x0 - 10, y: rect.y0 - 10), scene)
        let (resize, resized) = scene.drag(nil, from: a, to: outward, size: size, viewport: .initial,
                                           drawMode: false, area: rect, minimum: 5)
        guard case .resize(.a, rect) = resize else { Issue.record("expected a resize from A, got \(resize)"); return }
        let grown = resized.draft
        #expect(abs((grown?.x0 ?? 0) - (rect.x0 - 10)) < 1e-6 && abs((grown?.y0 ?? 0) - (rect.y0 - 10)) < 1e-6)
        #expect(grown?.x1 == rect.x1 && grown?.y1 == rect.y1, "the opposite corner stays")

        // Once chosen, the job stays even if the finger passes elsewhere.
        let (kept, _) = scene.drag(resize, from: .zero, to: .zero, size: size, viewport: .initial, drawMode: true, area: nil, minimum: 5)
        #expect(kept == resize)

        let mid = MapPoint(x: (rect.x0 + rect.x1) / 2, y: (rect.y0 + rect.y1) / 2)
        let centre = frame(mid, scene)
        let (move, moved) = scene.drag(nil, from: centre, to: frame(.init(x: mid.x + 8, y: mid.y), scene), size: size, viewport: .initial,
                                       drawMode: false, area: rect, minimum: 5)
        guard case .move = move else { Issue.record("expected a move, got \(move)"); return }
        #expect(moved.draft == .init(x0: rect.x0 + 8, x1: rect.x1 + 8, y0: rect.y0, y1: rect.y1))

        let (draw, drawn) = scene.drag(nil, from: centre, to: CGPoint(x: centre.x + 60, y: centre.y + 60), size: size, viewport: .initial,
                                       drawMode: true, area: nil, minimum: 5)
        guard case .draw = draw else { Issue.record("expected a draw, got \(draw)"); return }
        #expect(drawn.draft != nil && drawn.viewport == nil)

        let (pan, panned) = scene.drag(nil, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 25, y: 15), size: size, viewport: .init(zoom: 2),
                                       drawMode: false, area: nil, minimum: 5)
        guard case .pan = pan else { Issue.record("expected a pan, got \(pan)"); return }
        #expect(panned.draft == nil && panned.viewport != nil)
    }

    @Test func pinchingKeepsThePinchedPointUnderTheFingers() {
        let scene = scene
        let start = scene.pinchStart(at: CGPoint(x: 120, y: 200), size: size, viewport: .initial)
        #expect(start.zoom == 1 && start.at == MapPoint(x: 120, y: 200))
        let zoomed = scene.pinched(start, magnification: 3, size: size)
        #expect(zoomed.zoom == 3)
        let under = scene.matrix(size: size, viewport: zoomed).apply(start.anchor)
        #expect(abs(under.x - 120) < 1e-6 && abs(under.y - 200) < 1e-6)
        #expect(scene.pinched(start, magnification: 100, size: size).zoom == MapViewport.zoomRange.upperBound)
    }

    @MainActor @Test func voiceOverDrawAndActionsEditTheControllersArea() throws {
        let store = VacuumFixtures.store(.docked)
        let controller = VacuumController(vacuum: vacuum, store: store, caller: GalleryServiceRecorder(store: store))
        let state = VacuumMapState(vacuum: vacuum, loader: VacuumFixtures.loader(vacuum, scenario: .docked))
        state.refresh()
        let scene = try #require(state.scene)
        let editor = VacuumAreaEditor(controller: controller, mapState: state)
        let minimum = scene.minimumAreaCells(vacuum)

        editor.placeVoiceOverArea(scene)
        let placed = try #require(controller.areaSelection)
        #expect(placed == MapAreaEdit.voiceOverStart(scene.interactionGeometry, minimum: minimum))

        for nudge in MapAreaEdit.Nudge.allCases {
            let before = try #require(controller.areaSelection)
            editor.apply(nudge, to: before, scene: scene)
            #expect(controller.areaSelection == MapAreaEdit.nudge(before, nudge, interaction: scene.interactionGeometry, minimum: minimum),
                    "\(nudge.title)")
        }
    }
}
