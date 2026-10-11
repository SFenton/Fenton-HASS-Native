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
    @State private var gesture: MapAreaEdit.Gesture?
    /// True only while a map drag is live. Unlike `gesture`, it also resets when the system cancels the drag
    /// (no `onEnded`), so the page can never be left unscrollable.
    @GestureState private var dragging = false
    @State private var pinchStart: (zoom: Double, anchor: MapPoint, at: MapPoint)?
    @State private var draft: MapGridRect?

    init(controller: VacuumController, mapState: VacuumMapState) {
        self.controller = controller
        self.mapState = mapState
        _drawMode = State(initialValue: controller.areaSelection == nil)
    }

    private var area: MapGridRect? { draft ?? controller.areaSelection }
    private var minimumCells: Double { mapState.scene?.minimumAreaCells(controller.vacuum) ?? 5 }

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
        .scrollDisabled(dragging)
        .onChange(of: dragging) { _, live in if !live { gesture = nil } }
        .navigationTitle("\(controller.vacuum.title) Cleaning Area")
        .inlineNavigationTitle()
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            tool(controller.areaSelection == nil ? "Draw" : "Redraw", symbol: "rectangle.dashed", active: drawMode, id: "draw") {
                controller.areaSelection = nil
                if voiceOver, let scene = mapState.scene {
                    placeVoiceOverArea(scene)
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


    private func drag(_ scene: ValetudoMapScene, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard mapState.isReady, pinchStart == nil else { return }
                let (job, step) = scene.drag(gesture, from: value.startLocation, to: value.location, size: size, viewport: viewport,
                                             drawMode: drawMode, area: controller.areaSelection, minimum: minimumCells)
                gesture = job
                if let next = step.draft { draft = next }
                if let next = step.viewport { viewport = next }
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
                    pinchStart = scene.pinchStart(at: value.startLocation, size: size, viewport: viewport)
                    gesture = nil
                    draft = nil
                }
                guard let start = pinchStart else { return }
                viewport = scene.pinched(start, magnification: value.magnification, size: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    @ViewBuilder private func accessibilityEdits(_ scene: ValetudoMapScene) -> some View {
        if let rect = controller.areaSelection {
            ForEach(MapAreaEdit.Nudge.allCases, id: \.self) { nudge in
                Button(nudge.title) { apply(nudge, to: rect, scene: scene) }
            }
        }
    }

    /// A drag isn't available to VoiceOver, so its Draw places a centred area it can then move and resize.
    func placeVoiceOverArea(_ scene: ValetudoMapScene) {
        controller.areaSelection = MapAreaEdit.voiceOverStart(scene.interactionGeometry, minimum: minimumCells)
    }

    /// Applies one of the map's VoiceOver actions to the area.
    func apply(_ nudge: MapAreaEdit.Nudge, to rect: MapGridRect, scene: ValetudoMapScene) {
        controller.areaSelection = MapAreaEdit.nudge(rect, nudge, interaction: scene.interactionGeometry, minimum: minimumCells)
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

// MARK: - Editing math

extension ValetudoMapScene {
    /// Where a pinch started: the zoom then, the map point under the fingers and their frame point.
    typealias PinchStart = (zoom: Double, anchor: MapPoint, at: MapPoint)

    /// The smallest area side in cells (the vacuum's `minimumSizeCm`, 25 cm by default).
    func minimumAreaCells(_ vacuum: VacuumConfig) -> Double {
        ((vacuum.areaCleaning?.minimumSizeCm ?? 25) / interactionGeometry.pixelSize).rounded(.up)
    }

    /// The grid cell under a frame point.
    func gridPoint(_ point: CGPoint, size: CGSize, viewport: MapViewport) -> MapPoint {
        MapGeometry.gridPoint(geometry, matrix: matrix(size: size, viewport: viewport), framePoint: .init(x: point.x, y: point.y))
    }

    /// The resize handle within 22 pt (the web's hit radius) of a frame point.
    func corner(near point: CGPoint, of rect: MapGridRect, size: CGSize, viewport: MapViewport) -> MapGridRect.Corner? {
        let m = matrix(size: size, viewport: viewport)
        return MapGridRect.Corner.allCases.first { corner in
            let p = MapGeometry.framePoint(geometry, matrix: m, gridPoint: rect.point(corner))
            return hypot(p.x - point.x, p.y - point.y) <= 22
        }
    }

    /// One drag update: the drag's job (chosen on its first update, then kept) and what it changes.
    func drag(_ gesture: MapAreaEdit.Gesture?, from start: CGPoint, to location: CGPoint, size: CGSize, viewport: MapViewport,
              drawMode: Bool, area: MapGridRect?, minimum: Double) -> (MapAreaEdit.Gesture, MapAreaEdit.Step) {
        let job = gesture ?? MapAreaEdit.begin(
            start: gridPoint(start, size: size, viewport: viewport), location: start, drawMode: drawMode, area: area,
            corner: area.flatMap { corner(near: start, of: $0, size: size, viewport: viewport) }, viewport: viewport)
        let step = MapAreaEdit.update(job, current: gridPoint(location, size: size, viewport: viewport), location: location,
                                      stage: geometry, interaction: interactionGeometry, frame: size, rotation: rotation, minimum: minimum)
        return (job, step)
    }

    /// Starts a pinch at a frame point.
    func pinchStart(at point: CGPoint, size: CGSize, viewport: MapViewport) -> PinchStart {
        let at = MapPoint(x: point.x, y: point.y)
        return (viewport.zoom, matrix(size: size, viewport: viewport).inverted.apply(at), at)
    }

    /// The viewport after magnifying from `start`, keeping the pinched point under the fingers.
    func pinched(_ start: PinchStart, magnification: Double, size: CGSize) -> MapViewport {
        MapGeometry.viewport(geometry, frame: size, anchor: start.anchor, at: start.at, zoom: start.zoom * magnification, rotation: rotation)
    }
}
