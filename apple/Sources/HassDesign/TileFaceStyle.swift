import SwiftUI

/// Which of direction G's tile faces a tile draws (`.agents/design/direction-g.md`, Controls: Tiles; pattern:
/// `.agents/patterns/entity-tile.md`).
///
/// Pure, so the choice is unit-tested apart from the drawing in ``GlassTileFace``.
public enum TileFaceStyle: Equatable, Sendable {
    /// Dark ground, glyph in the family colour mixed toward grey (or secondary without a family).
    case off
    /// A light that is on: the warm lit tile with dark ink.
    case lit
    /// A device that is on: filled with its family colour, with the family's ink.
    case filled(ColorFamily)
    /// A tile whose caller has not picked a family yet: dark ground with the caller's tint on the glyph and rim.
    case tinted
    /// Something is wrong (no response, a fault): dark dense ground, red glyph and red state.
    case error

    /// The face for a tile's state.
    /// - Parameters:
    ///   - family: The device's colour family, or nil when the caller passes only a tint.
    ///   - isActive: Whether the device is on.
    ///   - isError: Whether the tile reports a fault.
    ///   - isUnavailable: Whether the entity is unavailable (drawn off and dimmed).
    public static func resolve(family: ColorFamily?, isActive: Bool, isError: Bool, isUnavailable: Bool) -> Self {
        if isError { return .error }
        if isUnavailable || !isActive { return .off }
        guard let family else { return .tinted }
        if family == .lights { return .lit }
        return family.spec.fill == nil ? .tinted : .filled(family)
    }

    /// Black over the part of a white-ink filled face that progress has not reached, so the done part reads as
    /// the lighter band.
    public static let progressShade = 0.18
    /// White over the done part of a dark-ink filled face (power).
    public static let progressLighten = 0.25

    /// Whether text on this face is dark (the lit tile and power's yellow).
    public var hasDarkInk: Bool {
        switch self {
        case .lit: true
        case let .filled(family): family.spec.darkInk
        default: false
        }
    }
}

// MARK: - Appearance

/// Whether a tile's neutral parts (off ground, title and state ink, glyph) are drawn for the dark or the light
/// appearance. Only a tile in a sheet under the light scheme is light: pages are always dark, and a lit or filled face
/// keeps its fixed fill and ink either way.
public enum TileAppearance: Equatable, Sendable {
    case dark
    case light

    /// The appearance for a tile on `surface` under `scheme`.
    public static func resolve(surface: TileSurface, scheme: ColorScheme) -> Self {
        surface == .sheet && scheme == .light ? .light : .dark
    }

    /// The scheme the appearance's colours are drawn for.
    public var scheme: ColorScheme { self == .light ? .light : .dark }

    /// The glyph and state colour of an error face: `#FF6961` on dark, a dark red on a light cell.
    public var errorRGB: UInt32 {
        self == .light ? HassTokens.Palette.redLight : HassTokens.Palette.red
    }

    /// How strongly a state wash tints the ground: 60% over a dark module, 22% over a white cell so the ink on it keeps
    /// 4.5:1.
    public var washOpacity: Double { self == .light ? 0.22 : 0.6 }
}

public extension TileFaceStyle {
    /// A caller's tint made legible as a glyph on a light cell: unchanged when it already reaches 3:1 (WCAG 1.4.11) on
    /// the sheet ground, else mixed toward black until it does, keeping its hue.
    /// - Parameter rgb: The tint's sRGB channels, 0 to 1.
    /// - Returns: The tint's channels, darkened as needed.
    static func lightGlyph(forTint rgb: (red: Double, green: Double, blue: Double)) -> (red: Double, green: Double, blue: Double) {
        func luminance(_ c: (red: Double, green: Double, blue: Double)) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
        }
        let ground = Double((HassTokens.Palette.sheetGroundLight >> 16) & 0xFF) / 255
        let groundLuminance = luminance((ground, ground, ground))
        func ratio(_ c: (red: Double, green: Double, blue: Double)) -> Double {
            let l = luminance(c)
            return (max(l, groundLuminance) + 0.05) / (min(l, groundLuminance) + 0.05)
        }
        var keep = 1.0
        var shaded = rgb
        while ratio(shaded) < 3.3, keep > 0 {
            keep -= 0.02
            shaded = (rgb.red * keep, rgb.green * keep, rgb.blue * keep)
        }
        return shaded
    }
}
