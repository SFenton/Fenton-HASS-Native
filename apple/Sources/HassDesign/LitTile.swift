import SwiftUI

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
