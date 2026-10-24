import CoreGraphics
import HassCore
import HassDesign
import SwiftUI

/// Draws a Valetudo map (pattern: `.agents/patterns/valetudo-map.md`; web `ValetudoMapCard.tsx`) in direction G's look:
/// flat neutral rooms on a dark card, selected rooms white with black numbered badges, skipped rooms hatched
/// (`.agents/design/direction-g.md`, Controls: Vacuum map).
///
/// Floor, segments and walls are rasterised once per map into a one-pixel-per-cell image that the canvas scales
/// with nearest-neighbour sampling, so pan and zoom only redraw vectors and icons. Each selectable room also gets a
/// mask once, which marks it selected or skipped without rasterising again. Rotation, the room focus crop and the
/// viewport come from ``MapGeometry``.
struct ValetudoMapCanvas: View {
    var scene: ValetudoMapScene
    var viewport: MapViewport = .initial
    /// Selected rooms and their cleaning order: drawn white with numbered badges.
    var roomOrders: [String: Int] = [:]
    /// Rooms the coordinator skips on automatic cleans: drawn hatched.
    var skippedRooms: Set<String> = []
    /// The area to outline.
    var area: MapGridRect?
    /// Draw corner handles on the area.
    var showsHandles = false

    var body: some View {
        Canvas { context, size in
            scene.draw(in: &context, size: size, viewport: viewport, roomOrders: roomOrders, skippedRooms: skippedRooms,
                       area: area, showsHandles: showsHandles)
        }
        .accessibilityHidden(true)
    }
}

/// A decoded map prepared for drawing: geometry, focus, rooms, the cell image and the room masks.
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
    /// One mask per drawn selectable room, keyed by its zone's entity id.
    let masks: [String: RoomMask]

    /// A room's cells as an opaque image in the selected colour, and where it sits on the stage.
    struct RoomMask {
        var image: CGImage
        /// The image's frame in stage cells.
        var rect: CGRect
        /// The room's bounds in grid cells, to test whether its name fits.
        var gridBounds: CGRect
    }

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
        var masks: [String: RoomMask] = [:]
        for room in rooms {
            if focused, !(room.segmentId.map(focus.acceptedSegmentIds.contains) ?? false) { continue }
            if let mask = Self.mask(room, geometry: geometry) { masks[room.entityId] = mask }
        }
        self.masks = masks
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

    // MARK: - Palette

    /// Direction G's map colours (mockup n6 `data-map`): a cool neutral ramp of rooms on a `#262628` card.
    enum Palette {
        /// The card and everything outside the rooms.
        static let ground = MapRGBA(38, 38, 40)
        /// Walls: the dark seams between rooms.
        static let wall = MapRGBA(30, 31, 34)
        /// Floor that belongs to no room.
        static let floor = MapRGBA(58, 63, 70)
        /// Room fills, cycled in layer order so neighbours differ slightly.
        static let rooms: [MapRGBA] = [
            MapRGBA(80, 86, 95), MapRGBA(90, 97, 107), MapRGBA(69, 75, 84), MapRGBA(86, 93, 102), MapRGBA(75, 81, 89),
            MapRGBA(64, 70, 78), MapRGBA(94, 101, 111), MapRGBA(77, 83, 92), MapRGBA(87, 94, 104), MapRGBA(71, 77, 85),
        ]
        /// A selected room.
        static let selected = MapRGBA(237, 239, 242)
        /// Stripes over a skipped room.
        static let hatch = MapRGBA(20, 21, 24, 0.75)
        /// Room names on a neutral room, and on a selected one.
        static let label = MapRGBA(255, 255, 255, 0.92)
        static let labelOnSelected = MapRGBA(28, 28, 30)
        /// Travelled and predicted paths.
        static let path = MapRGBA(138, 144, 153, 0.9)
        static let predictedPath = MapRGBA(138, 144, 153, 0.45)
        /// The robot: a white disc with a dark ring and centre, on a soft halo; grey once reported from memory.
        static let robot = MapRGBA(255, 255, 255)
        static let reportedRobot = MapRGBA(138, 144, 153)
        static let robotInk = MapRGBA(28, 28, 30)
        static let robotHalo = MapRGBA(255, 255, 255, 0.22)
        /// The dock.
        static let dock = MapRGBA(201, 205, 211)

        /// The fill for the segment at `index` among segments.
        static func room(_ index: Int) -> MapRGBA { rooms[index % rooms.count] }
    }

    // MARK: - Raster

    /// One premultiplied RGBA pixel per cell, alpha-blended in layer order (`renderValetudoMap` layer pass), in the
    /// flat G palette (no material texture).
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
            let color = layer.type == "wall" ? Palette.wall : isSegment ? Palette.room(segmentIndex) : Palette.floor
            if isSegment { segmentIndex += 1 }
            if let focus, isSegment, !(layer.segmentId.map(focus.acceptedSegmentIds.contains) ?? false) { continue }
            var index = 0
            while index + 1 < layer.pixels.count {
                let sx = Int(layer.pixels[index]), sy = Int(layer.pixels[index + 1])
                index += 2
                if let walls = focus?.renderWallCells, layer.type == "wall", !walls.contains(ValetudoMap.cellKey(sx, sy)) { continue }
                blend(sx - minX, sy - minY, color)
            }
        }
        return image(width: width, height: height, bytes: buffer.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) })
    }

    /// A room's mask: its cells, opaque, in ``Palette/selected``, cropped to the room's bounds.
    static func mask(_ room: ValetudoMap.SelectableRoom, geometry: MapStageGeometry) -> RoomMask? {
        let points = room.cells.map { (x: $0 / 100_000, y: $0 % 100_000) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let width = maxX - minX + 1, height = maxY - minY + 1
        guard width * height < 4_000_000 else { return nil }
        let color = Palette.selected
        let pixel: [UInt8] = [color.red, color.green, color.blue].map { UInt8(($0 * 255).rounded()) } + [255]
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for point in points {
            let index = ((point.y - minY) * width + (point.x - minX)) * 4
            bytes.replaceSubrange(index..<(index + 4), with: pixel)
        }
        guard let image = image(width: width, height: height, bytes: bytes) else { return nil }
        let rect = CGRect(x: CGFloat(minX - Int(geometry.minGridX)), y: CGFloat(minY - Int(geometry.minGridY)),
                          width: CGFloat(width), height: CGFloat(height))
        return RoomMask(image: image, rect: rect, gridBounds: CGRect(x: minX, y: minY, width: width, height: height))
    }

    private static func image(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Drawing

    func draw(in context: inout GraphicsContext, size: CGSize, viewport: MapViewport, roomOrders: [String: Int],
              skippedRooms: Set<String> = [], area: MapGridRect?, showsHandles: Bool) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color(Palette.ground)))
        let m = matrix(size: size, viewport: viewport)
        let scale = max(m.scale, 0.01)
        var stage = context
        stage.concatenate(CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.e, ty: m.f))
        if focus.mode == .focused { stage.clip(to: Path(CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height))) }
        if let cells {
            stage.draw(Image(decorative: cells, scale: 1).interpolation(.none),
                       in: CGRect(x: 0, y: 0, width: CGFloat(cells.width), height: CGFloat(cells.height)))
        }
        for (entityId, mask) in masks where roomOrders[entityId] != nil {
            stage.draw(Image(decorative: mask.image, scale: 1).interpolation(.none), in: mask.rect)
        }
        for (entityId, mask) in masks where skippedRooms.contains(entityId) {
            drawHatch(mask, in: stage, scale: scale)
        }
        drawVectors(in: &stage, scale: scale)
        drawIcons(in: &context, matrix: m)
        if let area { drawArea(area, in: &context, matrix: m, handles: showsHandles) }
        drawNames(in: &context, matrix: m, orders: roomOrders)
    }

    /// 45° stripes over a room, clipped to its cells (mockup n6-vacuum-autoclean).
    private func drawHatch(_ mask: RoomMask, in stage: GraphicsContext, scale: Double) {
        var hatch = stage
        hatch.clipToLayer { layer in
            layer.draw(Image(decorative: mask.image, scale: 1).interpolation(.none), in: mask.rect)
        }
        let r = mask.rect
        let step = 7 / scale
        var stripes = Path()
        var offset = -r.height
        while offset < r.width {
            stripes.move(to: CGPoint(x: r.minX + offset, y: r.maxY))
            stripes.addLine(to: CGPoint(x: r.minX + offset + r.height, y: r.minY))
            offset += step
        }
        hatch.stroke(stripes, with: .color(Self.color(Palette.hatch)), lineWidth: 2.4 / scale)
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
            let color = entity.type == "path" ? Palette.path : Palette.predictedPath
            stage.stroke(line, with: .color(Self.color(color)),
                         style: StrokeStyle(lineWidth: max(0.25, 2.2 / scale), lineCap: .round, lineJoin: .round))
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
                let dock = Path(roundedRect: CGRect(x: at.x - 5, y: at.y - 10, width: 10, height: 20), cornerRadius: 3.5)
                context.fill(dock, with: .color(Self.color(Palette.dock)))
                context.stroke(dock, with: .color(Self.color(Palette.wall)), lineWidth: 1.2)
            } else if entity.type == "robot_position" {
                drawRobot(at: at, reported: provenance == .reported, in: &context)
            }
        }
    }

    /// The robot: a white disc with a dark ring and centre on a soft halo (grey once reported from memory).
    private func drawRobot(at point: CGPoint, reported: Bool, in context: inout GraphicsContext) {
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        context.fill(circle(15), with: .color(Self.color(Palette.robotHalo)))
        context.fill(circle(9), with: .color(Self.color(reported ? Palette.reportedRobot : Palette.robot)))
        context.stroke(circle(9), with: .color(Self.color(Palette.robotInk)), lineWidth: 2.2)
        context.fill(circle(3), with: .color(Self.color(Palette.robotInk)))
    }

    private static func icon(_ symbol: String, at point: CGPoint, size: CGFloat, color: MapRGBA, halo: MapRGBA,
                             in context: inout GraphicsContext) {
        let radius = size * 0.62
        let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(self.color(halo)))
        context.stroke(circle, with: .color(self.color(ValetudoMapStyle.ring)), lineWidth: max(1.5, size * 0.08))
        var resolved = context.resolve(Image(systemName: symbol))
        resolved.shading = .color(self.color(color))
        context.draw(resolved, in: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
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
        context.fill(outline, with: .color(HassTokens.Ink.action.opacity(0.22)))
        context.stroke(outline, with: .color(HassTokens.Ink.action), lineWidth: 2)
        guard handles else { return }
        for point in points {
            let handle = Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            context.fill(handle, with: .color(.white))
            context.stroke(handle, with: .color(HassTokens.Ink.actionFill), lineWidth: 2)
        }
    }

    /// Room names, and over each selected room its order badge, centred on the room. A name is left out where it
    /// would not fit inside its room on screen (the mockup leaves small rooms unnamed).
    private func drawNames(in context: inout GraphicsContext, matrix m: Affine, orders: [String: Int]) {
        let badge: CGFloat = 22, gap: CGFloat = 3
        for room in rooms {
            guard let mask = masks[room.entityId] else { continue }
            let order = orders[room.entityId]
            let center = MapGeometry.framePoint(geometry, matrix: m, gridPoint: .init(x: room.centroid.x + 0.5, y: room.centroid.y + 0.5))
            let p = CGPoint(x: center.x, y: center.y)
            let box = frameSize(mask.gridBounds, m)
            let ink = order == nil ? Palette.label : Palette.labelOnSelected
            let name = context.resolve(Text(room.title).font(.caption2.weight(.semibold)).foregroundStyle(Self.color(ink)))
            let measured = name.measure(in: CGSize(width: 400, height: 100))
            let fits = measured.width + 8 <= box.width && measured.height + (order == nil ? 4 : badge + gap + 4) <= box.height
            switch (order, fits) {
            case let (order?, true):
                drawBadge(order, at: CGPoint(x: p.x, y: p.y - (measured.height + gap) / 2), size: badge, in: &context)
                context.draw(name, at: CGPoint(x: p.x, y: p.y + (badge + gap) / 2), anchor: .center)
            case let (order?, false):
                drawBadge(order, at: p, size: badge, in: &context)
            case (nil, true):
                context.draw(name, at: p, anchor: .center)
            case (nil, false):
                break
            }
        }
    }

    /// A grid rectangle's size on screen (the bounds of its rotated corners).
    private func frameSize(_ rect: CGRect, _ m: Affine) -> CGSize {
        let points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                      CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].map {
            MapGeometry.framePoint(geometry, matrix: m, gridPoint: .init(x: $0.x, y: $0.y))
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGSize(width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }

    private func drawBadge(_ order: Int, at point: CGPoint, size: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        context.fill(Path(ellipseIn: rect), with: .color(Self.color(Palette.labelOnSelected)))
        context.draw(Text("\(order)").font(.caption.bold()).foregroundStyle(.white), at: point)
    }

    static func color(_ rgba: MapRGBA) -> Color {
        Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
