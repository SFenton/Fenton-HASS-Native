import XCTest

/// Where a tile's ink sits, read from a screenshot. A tile is one accessibility element and its glyph and chevron are
/// hidden from VoiceOver, so XCUITest cannot ask for their frames; the pixels are the evidence (owner, 2026-10-16:
/// "chevrons vertically centred", "title and subtitle feel too high up").
@MainActor
enum TileGeometry {
    typealias RGB = (r: Int, g: Int, b: Int)

    /// The colour under a screen point, or nil when it is off the capture.
    static func rgb(at point: CGPoint, in capture: RenderedContrast.Capture) -> RGB? {
        let x = Int(point.x * capture.scale), y = Int(point.y * capture.scale)
        guard x >= 0, y >= 0, x < capture.width, y < capture.height else { return nil }
        let i = (y * capture.width + x) * 4
        return (Int(capture.pixels[i]), Int(capture.pixels[i + 1]), Int(capture.pixels[i + 2]))
    }

    /// The bounding box, in screen points, of the pixels inside `region` that differ from `background` by more than
    /// `threshold` (summed over the three channels), or nil when none do.
    static func inkBounds(in region: CGRect, background: RGB, threshold: Int = 150,
                          capture: RenderedContrast.Capture) -> CGRect? {
        let scale = capture.scale
        let minX = max(0, Int(region.minX * scale)), maxX = min(capture.width, Int(region.maxX * scale))
        let minY = max(0, Int(region.minY * scale)), maxY = min(capture.height, Int(region.maxY * scale))
        guard minX < maxX, minY < maxY else { return nil }
        var left = Int.max, right = -1, top = Int.max, bottom = -1
        for y in minY..<maxY {
            for x in minX..<maxX {
                let i = (y * capture.width + x) * 4
                let delta = abs(Int(capture.pixels[i]) - background.r) + abs(Int(capture.pixels[i + 1]) - background.g)
                    + abs(Int(capture.pixels[i + 2]) - background.b)
                guard delta > threshold else { continue }
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { return nil }
        return CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                      width: CGFloat(right - left + 1) / scale, height: CGFloat(bottom - top + 1) / scale)
    }

    /// Whether `colour` is within `tolerance` of `0xRRGGBB` on every channel.
    static func matches(_ colour: RGB, _ hex: UInt32, tolerance: Int = 8) -> Bool {
        abs(colour.r - Int((hex >> 16) & 0xFF)) <= tolerance && abs(colour.g - Int((hex >> 8) & 0xFF)) <= tolerance
            && abs(colour.b - Int(hex & 0xFF)) <= tolerance
    }

    /// The chevron's ink inside a tile: the trailing 32 pt, clear of the tile's rounded corners (top and bottom 14 pt).
    /// - Parameters:
    ///   - frame: The tile's frame in screen points.
    ///   - capture: A capture of the screen the tile is on.
    /// - Returns: The chevron's bounding box, or nil when none is drawn. The tile must have a flat fill.
    static func chevron(in frame: CGRect, capture: RenderedContrast.Capture) -> CGRect? {
        guard let background = rgb(at: CGPoint(x: frame.maxX - 18, y: frame.minY + 6), in: capture) else { return nil }
        let region = CGRect(x: frame.maxX - 32, y: frame.minY + 14, width: 28, height: frame.height - 28)
        return inkBounds(in: region, background: background, capture: capture)
    }

    /// The glyph and text ink inside a flat-filled tile, clear of the chevron column.
    static func content(in frame: CGRect, capture: RenderedContrast.Capture, reservesChevron: Bool = true) -> CGRect? {
        guard let background = rgb(at: CGPoint(x: frame.minX + 8, y: frame.maxY - 8), in: capture) else { return nil }
        let region = CGRect(x: frame.minX + 6, y: frame.minY + 4,
                            width: frame.width - 12 - (reservesChevron ? 30 : 0), height: frame.height - 8)
        return inkBounds(in: region, background: background, capture: capture)
    }
}
