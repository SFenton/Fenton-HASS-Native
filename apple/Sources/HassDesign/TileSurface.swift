import SwiftUI

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
