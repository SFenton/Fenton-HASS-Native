import CoreGraphics
import HassCore
import HassDesign
import SwiftUI

/// Draws a Valetudo map (pattern: `.agents/patterns/valetudo-map.md`; web `ValetudoMapCard.tsx`).
///
/// Floor, segments and walls are rasterised once per map into a one-pixel-per-cell image that the canvas scales
/// with nearest-neighbour sampling, so pan and zoom only redraw vectors and icons. Rotation, the room focus crop
/// and the viewport come from ``MapGeometry``.
struct ValetudoMapCanvas: View {
    var scene: ValetudoMapScene
    var viewport: MapViewport = .initial
    /// Selected rooms and their cleaning order, drawn as numbered badges.
    var roomOrders: [String: Int] = [:]
    /// The area to outline.
    var area: MapGridRect?
    /// Draw corner handles on the area.
    var showsHandles = false

    var body: some View {
        Canvas { context, size in
            scene.draw(in: &context, size: size, viewport: viewport, roomOrders: roomOrders, area: area, showsHandles: showsHandles)
        }
        .accessibilityHidden(true)
    }
}

/// A decoded map prepared for drawing: geometry, focus, rooms and the cell image.
struct ValetudoMapScene {
    let map: ValetudoMap
    let provenance: ValetudoMapProvenance
    let rotation: Double
    let focus: ValetudoMapFocus
    /// Drawing geometry (the focus view when focused).
    let geometry: MapStageGeometry
    /// Where an area may be drawn.
    let interactionGeometry: MapStageGeometry
    let rooms: [ValetudoMap.SelectableRoom]
    let cells: CGImage?

    init(map: ValetudoMap, vacuum: VacuumConfig, provenance: ValetudoMapProvenance) {
        self.map = map
        self.provenance = provenance
        rotation = vacuum.mapRotationDegrees
        focus = ValetudoMapFocus.resolve(map, policy: vacuum.mapFocus)
        let focused = focus.mode == .focused
        geometry = MapStageGeometry(map: map, mapScale: vacuum.mapScale, bounds: focused ? focus.viewBounds : nil)
        interactionGeometry = MapStageGeometry(map: map, mapScale: vacuum.mapScale, bounds: focused ? focus.interactionBounds : nil)
        rooms = vacuum.mapRoomSelection ? map.selectableRooms(vacuum.zones) : []
        cells = Self.rasterise(map, geometry: geometry, focus: focused ? focus : nil)
    }

    /// Width over height, for the frame.
    var aspectRatio: Double { MapGeometry.aspectRatio(geometry, rotation: rotation) }

    /// The local → frame transform.
    func matrix(size: CGSize, viewport: MapViewport) -> Affine {
        MapGeometry.matrix(geometry, frame: size, viewport: viewport, rotation: rotation)
    }

    /// The room under a frame point.
    func room(at point: CGPoint, size: CGSize, viewport: MapViewport = .initial) -> ValetudoMap.SelectableRoom? {
        let grid = MapGeometry.gridPoint(geometry, matrix: matrix(size: size, viewport: viewport), framePoint: .init(x: point.x, y: point.y))
        return ValetudoMap.room(at: (grid.x, grid.y), in: rooms)
    }

    // MARK: - Raster

    /// One premultiplied RGBA pixel per cell, alpha-blended in layer order (`renderValetudoMap` layer pass).
    static func rasterise(_ map: ValetudoMap, geometry: MapStageGeometry, focus: ValetudoMapFocus?) -> CGImage? {
        let width = Int(geometry.width.rounded(.up)), height = Int(geometry.height.rounded(.up))
        guard width > 0, height > 0, width * height < 16_000_000 else { return nil }
        var buffer = [Double](repeating: 0, count: width * height * 4)
        func blend(_ x: Int, _ y: Int, _ color: MapRGBA) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let index = (y * width + x) * 4
            let a = color.alpha, keep = 1 - a
            buffer[index] = color.red * a + buffer[index] * keep
            buffer[index + 1] = color.green * a + buffer[index + 1] * keep
            buffer[index + 2] = color.blue * a + buffer[index + 2] * keep
            buffer[index + 3] = a + buffer[index + 3] * keep
        }
        let minX = Int(geometry.minGridX), minY = Int(geometry.minGridY)
        var segmentIndex = 0
        for layer in map.layers where !layer.pixels.isEmpty {
            let isSegment = layer.type == "segment"
            let color = layer.type == "wall" ? ValetudoMapStyle.wall : ValetudoMapStyle.segment(segmentIndex)
            if isSegment { segmentIndex += 1 }
            if let focus, isSegment, !(layer.segmentId.map(focus.acceptedSegmentIds.contains) ?? false) { continue }
            let material = isSegment ? layer.material : nil
            var index = 0
            while index + 1 < layer.pixels.count {
                let sx = Int(layer.pixels[index]), sy = Int(layer.pixels[index + 1])
                index += 2
                if let walls = focus?.renderWallCells, layer.type == "wall", !walls.contains(ValetudoMap.cellKey(sx, sy)) { continue }
                blend(sx - minX, sy - minY, color)
                if let accent = ValetudoMapStyle.accent(material, x: sx, y: sy) { blend(sx - minX, sy - minY, ValetudoMapStyle.color(accent)) }
            }
        }
        let bytes = buffer.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Drawing

    func draw(in context: inout GraphicsContext, size: CGSize, viewport: MapViewport, roomOrders: [String: Int],
              area: MapGridRect?, showsHandles: Bool) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color(ValetudoMapStyle.background)))
        let m = matrix(size: size, viewport: viewport)
        let scale = max(m.scale, 0.01)
        var stage = context
        stage.concatenate(CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.e, ty: m.f))
        if focus.mode == .focused { stage.clip(to: Path(CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height))) }
        if let cells {
            stage.draw(Image(decorative: cells, scale: 1).interpolation(.none),
                       in: CGRect(x: 0, y: 0, width: CGFloat(cells.width), height: CGFloat(cells.height)))
        }
        drawVectors(in: &stage, scale: scale)
        drawIcons(in: &context, matrix: m)
        if let area { drawArea(area, in: &context, matrix: m, handles: showsHandles) }
        drawBadges(in: &context, matrix: m, orders: roomOrders)
    }

    private func local(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x / geometry.pixelSize - geometry.minGridX, y: y / geometry.pixelSize - geometry.minGridY)
    }

    private func path(_ entity: ValetudoMap.Entity, closed: Bool) -> Path? {
        let points = entity.points
        guard points.count >= (closed ? 6 : 4) else { return nil }
        var path = Path()
        path.move(to: local(points[0], points[1]))
        var index = 2
        while index + 1 < points.count {
            path.addLine(to: local(points[index], points[index + 1]))
            index += 2
        }
        if closed { path.closeSubpath() }
        return path
    }

    private func drawVectors(in stage: inout GraphicsContext, scale: Double) {
        for entity in map.entities where entity.type == "path" || entity.type == "predicted_path" {
            guard let line = path(entity, closed: false) else { continue }
            let color = entity.type == "path" ? ValetudoMapStyle.path : ValetudoMapStyle.predictedPath
            stage.stroke(line, with: .color(Self.color(color)),
                         style: StrokeStyle(lineWidth: max(0.25, 2 / scale), lineCap: .round, lineJoin: .round))
        }
        for entity in map.entities {
            guard let style = ValetudoMapStyle.entityStyle(entity.type), style.shape != .point,
                  let shape = path(entity, closed: style.shape == .polygon) else { continue }
            let dash = style.dash.map { CGFloat($0 / scale) }
            if style.shape == .polygon {
                if let fill = style.fill { stage.fill(shape, with: .color(Self.color(fill))) }
                stage.stroke(shape, with: .color(Self.color(style.stroke)), style: StrokeStyle(lineWidth: max(0.2, 2 / scale), dash: dash))
            } else {
                stage.stroke(shape, with: .color(Self.color(style.stroke)),
                             style: StrokeStyle(lineWidth: max(0.3, 3 / scale), lineCap: .round, lineJoin: .round, dash: dash))
            }
        }
    }

    private func framePoint(_ entity: ValetudoMap.Entity, _ m: Affine) -> CGPoint? {
        guard entity.points.count >= 2 else { return nil }
        let point = local(entity.points[0], entity.points[1])
        let frame = m.apply(.init(x: point.x, y: point.y))
        return CGPoint(x: frame.x, y: frame.y)
    }

    private func drawIcons(in context: inout GraphicsContext, matrix m: Affine) {
        for entity in map.entities {
            guard let style = ValetudoMapStyle.entityStyle(entity.type), style.shape == .point, let icon = style.icon,
                  let at = framePoint(entity, m) else { continue }
            Self.icon(icon == .obstacle ? "exclamationmark.circle.fill" : "mappin", at: at, size: icon == .obstacle ? 15 : 18,
                      color: style.stroke, halo: style.halo ?? ValetudoMapStyle.halo, in: &context)
        }
        for entity in map.entities {
            guard let at = framePoint(entity, m) else { continue }
            if entity.type == "charger_location" {
                Self.icon("bolt.fill", at: at, size: 22, color: ValetudoMapStyle.dock, halo: ValetudoMapStyle.dockHalo, in: &context)
            } else if entity.type == "robot_position" {
                let reported = provenance == .reported
                let obstacle = ValetudoMapStyle.entityStyle("obstacle")
                Self.icon("circle.circle.fill", at: at, size: 22, color: reported ? obstacle?.stroke ?? ValetudoMapStyle.liveRobot : ValetudoMapStyle.liveRobot,
                          halo: reported ? obstacle?.halo ?? ValetudoMapStyle.halo : ValetudoMapStyle.halo,
                          rotation: rotation + (entity.angle ?? 0) - 90, in: &context)
            }
        }
    }

    private static func icon(_ symbol: String, at point: CGPoint, size: CGFloat, color: MapRGBA, halo: MapRGBA,
                             rotation: Double = 0, in context: inout GraphicsContext) {
        let radius = size * 0.62
        let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(self.color(halo)))
        context.stroke(circle, with: .color(self.color(ValetudoMapStyle.ring)), lineWidth: max(1.5, size * 0.08))
        var resolved = context.resolve(Image(systemName: symbol))
        resolved.shading = .color(self.color(color))
        var icon = context
        icon.translateBy(x: point.x, y: point.y)
        icon.rotate(by: .degrees(rotation))
        icon.draw(resolved, in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
    }

    private func corners(_ rect: MapGridRect, _ m: Affine) -> [CGPoint] {
        MapGridRect.Corner.allCases.map { corner in
            let p = MapGeometry.framePoint(geometry, matrix: m, gridPoint: rect.point(corner))
            return CGPoint(x: p.x, y: p.y)
        }
    }

    private func drawArea(_ rect: MapGridRect, in context: inout GraphicsContext, matrix m: Affine, handles: Bool) {
        let points = corners(rect, m)
        var outline = Path()
        outline.addLines(points)
        outline.closeSubpath()
        context.fill(outline, with: .color(Color(red: 0.31, green: 0.76, blue: 0.97).opacity(0.22)))
        context.stroke(outline, with: .color(Color(red: 0.51, green: 0.83, blue: 0.98)), lineWidth: 2)
        guard handles else { return }
        for point in points {
            let handle = Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            context.fill(handle, with: .color(.white))
            context.stroke(handle, with: .color(Color(red: 0.0, green: 0.42, blue: 0.82)), lineWidth: 2)
        }
    }

    private func drawBadges(in context: inout GraphicsContext, matrix m: Affine, orders: [String: Int]) {
        for room in rooms {
            guard let order = orders[room.entityId] else { continue }
            let p = MapGeometry.framePoint(geometry, matrix: m, gridPoint: .init(x: room.centroid.x, y: room.centroid.y))
            let rect = CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)
            context.fill(Path(ellipseIn: rect), with: .color(VacuumStyle.primaryFill))
            context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
            context.draw(Text("\(order)").font(.caption.weight(.bold)).foregroundStyle(.white), at: CGPoint(x: p.x, y: p.y))
        }
    }

    static func color(_ rgba: MapRGBA) -> Color {
        Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
