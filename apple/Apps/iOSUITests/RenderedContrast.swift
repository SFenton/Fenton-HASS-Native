import XCTest

/// Rendered-pixel contrast, the evidence for a contrast issue the audit misjudges (FestivalNativeApps
/// `IPadAuditRenderedContrast`, simplified). The iPad audit fails dark text on light materials that
/// measure well above 4.5:1 on screen; this measures the element's own frame in a capture from the same
/// run: the glyph pixels' upper quartile (text core) against the median pixel (surface), as a WCAG ratio.
@MainActor
enum RenderedContrast {
    /// A full-screen capture as RGBA bytes, with its scale to screen points.
    struct Capture {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat

        static func screen() -> Capture? {
            let screenshot = XCUIScreen.main.screenshot()
            // Draw through UIImage so the capture follows the interface orientation: the raw CGImage stays
            // portrait in landscape while element frames are landscape (seen on iPad, 2026-10-11).
            let format = UIGraphicsImageRendererFormat()
            format.scale = screenshot.image.scale
            let upright = UIGraphicsImageRenderer(size: screenshot.image.size, format: format).image { _ in
                screenshot.image.draw(at: .zero)
            }
            guard let image = upright.cgImage else { return nil }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            return Capture(pixels: pixels, width: width, height: height, scale: screenshot.image.scale)
        }
    }

    /// WCAG contrast of the text against its surface inside `frame` (screen points), or nil when the
    /// frame is empty or off the capture.
    static func ratio(of frame: CGRect, in capture: Capture) -> Double? {
        let rect = CGRect(
            x: frame.minX * capture.scale, y: frame.minY * capture.scale,
            width: frame.width * capture.scale, height: frame.height * capture.scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: capture.width, height: capture.height))
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        var luminances: [Double] = []
        luminances.reserveCapacity(Int(rect.width * rect.height))
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * capture.width + x) * 4
                luminances.append(luminance(capture.pixels[i], capture.pixels[i + 1], capture.pixels[i + 2]))
            }
        }
        let sorted = luminances.sorted()
        let surface = sorted[sorted.count / 2]
        // Glyph pixels differ clearly from the surface; their upper quartile of distance is the text core.
        let glyphs = luminances.filter { abs($0 - surface) > 0.05 }.sorted { abs($0 - surface) < abs($1 - surface) }
        guard !glyphs.isEmpty else { return 1 }
        let text = glyphs[(glyphs.count * 3) / 4]
        return (max(text, surface) + 0.05) / (min(text, surface) + 0.05)
    }

    private static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
