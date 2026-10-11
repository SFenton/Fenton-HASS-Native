import HassCore
import HassDesign
import SwiftUI

/// Draws one rectangular cleaning area on the map (web area editor in `VacuumMapAndStatus` and the
/// `ValetudoMapCard` pointer gestures).
///
/// Draw mode: drag to draw. Otherwise drag inside the area to move it, drag a corner handle to resize it, or drag
/// elsewhere to pan; pinch zooms 1–10×. VoiceOver gets the same edits as actions on the map.
struct VacuumAreaEditor: View {
    var controller: VacuumController
    var mapState: VacuumMapState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var drawMode: Bool
    @State private var viewport = MapViewport.initial
    @State private var gesture: EditGesture?
    @State private var pinchStart: (zoom: Double, anchor: MapPoint, at: MapPoint)?
    @State private var draft: MapGridRect?

    init(controller: VacuumController, mapState: VacuumMapState) {
        self.controller = controller
        self.mapState = mapState
        _drawMode = State(initialValue: controller.areaSelection == nil)
    }

    /// What the current drag does.
    enum EditGesture {
        case draw(anchor: MapPoint)
        case move(origin: MapGridRect, start: MapPoint)
        case resize(corner: MapGridRect.Corner, origin: MapGridRect)
        case pan(origin: MapViewport, start: CGPoint)
    }

    private var area: MapGridRect? { draft ?? controller.areaSelection }
    private var minimumCells: Double {
        guard let scene = mapState.scene else { return 5 }
        return ((controller.vacuum.areaCleaning?.minimumSizeCm ?? 25) / scene.interactionGeometry.pixelSize).rounded(.up)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                toolbar
                if let scene = mapState.scene {
                    editor(scene)
                } else {
                    VacuumNotice("Map Unavailable", tone: .warning, text: "Home Assistant cannot currently confirm the vacuum's map or position.")
                }
                summary
            }
            .padding(HassTokens.Spacing.l)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(gesture != nil)
        .navigationTitle("\(controller.vacuum.title) Cleaning Area")
        .inlineNavigationTitle()
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            tool(controller.areaSelection == nil ? "Draw" : "Redraw", symbol: "rectangle.dashed", active: drawMode, id: "draw") {
                controller.areaSelection = nil
                if voiceOver, let scene = mapState.scene {
                    // A drag isn't available to VoiceOver: start from a centred area it can then move and resize.
                    controller.areaSelection = MapGeometry.defaultRect(scene.interactionGeometry, size: max(30, minimumCells))
                    drawMode = false
                } else {
                    drawMode = true
                }
            }
            tool("Reset View", symbol: "arrow.up.left.and.arrow.down.right", id: "reset") { viewport = .initial }
            tool("Clear", symbol: "trash", id: "clear", disabled: controller.areaSelection == nil) {
                controller.areaSelection = nil
                drawMode = true
            }
        }
        .disabled(!mapState.isReady)
    }

    private func tool(_ title: String, symbol: String, active: Bool = false, id: String, disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                .foregroundStyle(active ? Color.white : HassTokens.Ink.primary)
                .background(active ? AnyShapeStyle(VacuumStyle.primaryFill) : AnyShapeStyle(VacuumStyle.rowFill), in: VacuumStyle.rowShape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("vacuum.area.\(id)")
    }

    // MARK: - Map

    private func editor(_ scene: ValetudoMapScene) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            GeometryReader { proxy in
                ValetudoMapCanvas(scene: scene, viewport: viewport, area: area, showsHandles: !drawMode)
                    .contentShape(Rectangle())
                    .gesture(drag(scene, size: proxy.size))
                    .simultaneousGesture(pinch(scene, size: proxy.size))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(controller.vacuum.title) cleaning area editor")
                    .accessibilityValue(dimensionsText ?? "No area selected")
                    .accessibilityActions { accessibilityEdits(scene) }
                    .accessibilityIdentifier("vacuum.area.map")
            }
            .aspectRatio(max(scene.aspectRatio, 0.6), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
            Text(drawMode ? "Drag on the map to draw the cleaning area."
                 : area != nil ? "Drag the area to move it or use any round corner handle to resize." : "Choose Draw, then drag on the map.")
                .font(.footnote)
                .foregroundStyle(HassTokens.Ink.secondary)
        }
    }

    private func grid(_ scene: ValetudoMapScene, _ point: CGPoint, _ size: CGSize) -> MapPoint {
        MapGeometry.gridPoint(scene.geometry, matrix: scene.matrix(size: size, viewport: viewport), framePoint: .init(x: point.x, y: point.y))
    }

    /// The corner within reach of a frame point (22 pt, the web's hit radius).
    private func corner(near point: CGPoint, _ scene: ValetudoMapScene, _ size: CGSize, _ rect: MapGridRect) -> MapGridRect.Corner? {
        let m = scene.matrix(size: size, viewport: viewport)
        return MapGridRect.Corner.allCases.first { corner in
            let p = MapGeometry.framePoint(scene.geometry, matrix: m, gridPoint: rect.point(corner))
            return hypot(p.x - point.x, p.y - point.y) <= 22
        }
    }

    private func drag(_ scene: ValetudoMapScene, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard mapState.isReady, pinchStart == nil else { return }
                let interaction = scene.interactionGeometry
                if gesture == nil {
                    let start = grid(scene, value.startLocation, size)
                    if drawMode {
                        gesture = .draw(anchor: start)
                    } else if let rect = controller.areaSelection, let corner = corner(near: value.startLocation, scene, size, rect) {
                        gesture = .resize(corner: corner, origin: rect)
                    } else if let rect = controller.areaSelection, start.x >= rect.x0, start.x <= rect.x1, start.y >= rect.y0, start.y <= rect.y1 {
                        gesture = .move(origin: rect, start: start)
                    } else {
                        gesture = .pan(origin: viewport, start: value.startLocation)
                    }
                }
                let current = grid(scene, value.location, size)
                switch gesture {
                case let .draw(anchor): draft = MapGeometry.rect(interaction, from: anchor, to: current, minimum: minimumCells)
                case let .move(origin, start):
                    draft = MapGeometry.translate(interaction, origin, by: .init(x: current.x - start.x, y: current.y - start.y))
                case let .resize(corner, origin): draft = MapGeometry.resize(interaction, origin, corner: corner, to: current, minimum: minimumCells)
                case let .pan(origin, start):
                    var next = origin
                    next.panX += value.location.x - start.x
                    next.panY += value.location.y - start.y
                    viewport = MapGeometry.clamp(scene.geometry, frame: size, viewport: next, rotation: scene.rotation)
                case nil: break
                }
            }
            .onEnded { _ in
                if let draft {
                    controller.areaSelection = draft
                    drawMode = false
                }
                draft = nil
                gesture = nil
            }
    }

    private func pinch(_ scene: ValetudoMapScene, size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil {
                    let at = MapPoint(x: value.startLocation.x, y: value.startLocation.y)
                    let local = scene.matrix(size: size, viewport: viewport).inverted.apply(at)
                    pinchStart = (viewport.zoom, local, at)
                    gesture = nil
                    draft = nil
                }
                guard let start = pinchStart else { return }
                viewport = MapGeometry.viewport(scene.geometry, frame: size, anchor: start.anchor, at: start.at,
                                                zoom: start.zoom * value.magnification, rotation: scene.rotation)
            }
            .onEnded { _ in pinchStart = nil }
    }

    @ViewBuilder private func accessibilityEdits(_ scene: ValetudoMapScene) -> some View {
        if let rect = controller.areaSelection {
            let g = scene.interactionGeometry, step = max(2, minimumCells / 2)
            Button("Move area left") { controller.areaSelection = MapGeometry.translate(g, rect, by: .init(x: -step, y: 0)) }
            Button("Move area right") { controller.areaSelection = MapGeometry.translate(g, rect, by: .init(x: step, y: 0)) }
            Button("Move area up") { controller.areaSelection = MapGeometry.translate(g, rect, by: .init(x: 0, y: -step)) }
            Button("Move area down") { controller.areaSelection = MapGeometry.translate(g, rect, by: .init(x: 0, y: step)) }
            Button("Make area larger") {
                controller.areaSelection = MapGeometry.resize(g, rect, corner: .c, to: .init(x: rect.x1 + step, y: rect.y1 + step), minimum: minimumCells)
            }
            Button("Make area smaller") {
                controller.areaSelection = MapGeometry.resize(g, rect, corner: .c, to: .init(x: rect.x1 - step, y: rect.y1 - step), minimum: minimumCells)
            }
        }
    }

    // MARK: - Summary

    private var dimensionsText: String? {
        guard let area, let scene = mapState.scene else { return nil }
        let size = area.dimensionsCm(pixelSize: scene.interactionGeometry.pixelSize)
        return "\(VacuumFormat.metres(size.width)) × \(VacuumFormat.metres(size.height))"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dimensionsText ?? "No area selected")
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .accessibilityIdentifier("vacuum.area.dimensions")
                Text(squareMetres ?? "Draw a rectangle to continue.")
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            .accessibilityElement(children: .combine)
            VacuumDescription("Drag to draw an area, drag inside it to move it, and drag any round corner handle to resize it. Pinch to zoom.")
            if !mapState.allows(controller.areaSelection) {
                VacuumNotice(nil, tone: .warning, text: "The area must stay inside the rooms shown on the map.")
            }
            VacuumActionButton(action: .init(kind: .cleanArea, title: controller.areaSelection == nil ? "Draw an Area to Continue" : "Use This Area",
                                             icon: "mdi:check", tone: .primary, detail: nil,
                                             isDisabled: controller.areaSelection == nil || !mapState.isReady),
                               identifier: "vacuum.area.use") {
                dismiss()
            }
        }
    }

    private var squareMetres: String? {
        guard let area, let scene = mapState.scene else { return nil }
        let size = area.dimensionsCm(pixelSize: scene.interactionGeometry.pixelSize)
        return String(format: "%.2f m² selected", size.width * size.height / 10_000)
    }
}
