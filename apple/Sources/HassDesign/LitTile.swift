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
    /// How strong the status text is: `#1C1C1E` at 85%. At 72% it measured 4.2:1 on a blue bulb's band (Custom
    /// Lights, "41%"); 85% keeps 5.3:1 under the strongest bulb tint (``bulbTint``).
    static let secondaryInkOpacity = 0.85
    /// Status text on the lit tile.
    static let secondaryInk = Color(rgb: 0x1C1C1E).opacity(secondaryInkOpacity)
    /// How much a coloured bulb tints its band.
    static let bulbTint = 0.3

    /// Power's fill runs from a lighter yellow at the top.
    static let powerTop = Color(rgb: 0xFFE45C)
}
