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

    /// Whether text on this face is dark (the lit tile and power's yellow).
    public var hasDarkInk: Bool {
        switch self {
        case .lit: true
        case let .filled(family): family.spec.darkInk
        default: false
        }
    }
}

/// Where a tile sits, which sets the ground of its dark faces.
public enum TileSurface: Sendable {
    /// On the wallpaper: the thin module material.
    case page
    /// Inside a sheet: the sheet's cell colour, `#2C2C2E`.
    case sheet
}

public extension EnvironmentValues {
    /// Where tiles inside are drawn (``TileSurface``). `modalChrome()` sets `.sheet`.
    @Entry var tileSurface: TileSurface = .page
}

/// Direction G's lit tile for lights that are on (direction-g.md, Colour families: Lights).
enum LitTile {
    /// The bright band, top to bottom.
    static let bandTop = Color(rgb: 0xFFF3DE)
    static let bandBottom = Color(rgb: 0xFFE2B2)
    /// The tile under the band, past the brightness level.
    static let base = Color(rgb: 0xEADBC4)
    /// The bulb glyph.
    static let glyph = Color(rgb: 0xD97A00)
    /// Titles on the lit tile.
    static let ink = Color(rgb: 0x1C1C1E)
    /// Status text on the lit tile (`#1C1C1E` at 72%: 7:1 or better on the base).
    static let secondaryInk = Color(rgb: 0x1C1C1E).opacity(0.72)

    /// Power's fill runs from a lighter yellow at the top.
    static let powerTop = Color(rgb: 0xFFE45C)
}
