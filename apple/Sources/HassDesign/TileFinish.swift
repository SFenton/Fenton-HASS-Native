import SwiftUI

/// How a tile's surface is finished: the shipped solid fills, or one of three "frosted" proposals the owner can choose
/// between (owner, 2026-10-16: "Ideate on a more 'frosted' tile look like we have on the web; subtle but looks less
/// childish"). Proposals only: nothing ships a finish other than ``solid`` until the owner picks one
/// (`.agents/design/direction-g.md`, Tile finish).
///
/// **No live blur.** Every finish is built from translucency over the wallpaper (which is blurred once and cached), a
/// gradient and a hairline, never `.blur` or a material per tile, which cost GPU time and crashed the render server
/// (direction-g.md, Layers; performance.md). The frost reads from a milky veil, a soft top light and a lit edge.
///
/// **HIG.** Tiles are content-layer elements, so none uses Liquid Glass (HIG, Materials: "Don't use Liquid Glass in the
/// content layer"); translucency and a hairline stand in for a standard material. With Reduce Transparency or Increase
/// Contrast every finish falls back to ``solid`` (HIG, Accessibility).
public enum TileFinish: String, CaseIterable, Identifiable, Sendable {
    /// Shipped: a solid family fill (or the thin module for off) with a faint top highlight.
    case solid
    /// A: the family fill at 78% over a dark underlay, so the wallpaper tints it, with a lit hairline and a soft top highlight.
    case tintedGlass
    /// B: one neutral frosted module for every state; the family colour moves to a glyph disc and a coloured edge glow.
    case frostedModule
    /// C: the web's tile (`GlassTile.module.css`, `Card.module.css`) as closely as contrast allows: a milky white veil for
    /// off, the tint at web strength for on, a diagonal sheen, inset top and bottom lines.
    case webPort

    public var id: String { rawValue }

    /// The finish every tile uses unless the environment says otherwise. A debug build reads `FENTON_TILE_FINISH`
    /// (`solid`, `tintedGlass`, `frostedModule`, `webPort`) so the scroll cost probe can measure each on real pages.
    public static let standard: TileFinish = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["FENTON_TILE_FINISH"], let finish = TileFinish(rawValue: name) {
            return finish
        }
        #endif
        return .solid
    }()

    /// Layers a Debug launch leaves out (`FENTON_TILE_FINISH_OMIT=sheen,rim`), to measure what each costs the scroll
    /// (performance.md). Always empty in a Release build.
    static let omitted: Set<String> = {
        #if DEBUG
        return Set((ProcessInfo.processInfo.environment["FENTON_TILE_FINISH_OMIT"] ?? "").split(separator: ",").map(String.init))
        #else
        return []
        #endif
    }()

    /// The gallery's name for the finish.
    public var title: String {
        switch self {
        case .solid: "Solid (Shipped)"
        case .tintedGlass: "A  Tinted Glass"
        case .frostedModule: "B  Frosted Module"
        case .webPort: "C  Web Port"
        }
    }

    /// A one-line description for the gallery.
    public var summary: String {
        switch self {
        case .solid: "Opaque family fill, thin dark module when off."
        case .tintedGlass: "Family tint at 78% over the wallpaper, lit hairline, soft top light."
        case .frostedModule: "One neutral frosted module; colour lives in a glyph disc and the edge."
        case .webPort: "The web's milky veil, tint and sheen, deepened until white reads."
        }
    }

    /// How much of the family colour an off glyph keeps (``ColorFamily/offGlyphRGB(_:keep:)``): the shipped 72%, or more on
    /// a frosted ground, which is a little lighter than the thin module.
    public var offGlyphKeep: Double { self == .solid ? 0.72 : 0.88 }

    /// Finish B's off disc: black over the module, so the glyph sits in a shallow well and keeps its contrast.
    public static let offDiscShade: (dark: Double, light: Double) = (0.22, 0.06)

    /// Whether the finish draws a coloured glyph disc (B) instead of a bare glyph.
    public var usesGlyphDisc: Bool { self == .frostedModule }

    /// The finish a tile draws: the preferred one, or ``solid`` when the person turned on Reduce Transparency or Increase
    /// Contrast (HIG, Accessibility), which keeps every ground opaque.
    public static func effective(_ preferred: TileFinish, reduceTransparency: Bool, increasedContrast: Bool) -> TileFinish {
        reduceTransparency || increasedContrast ? .solid : preferred
    }

    /// Tokens (``Tokens``) for the page and the sheet.
    public func tokens(on surface: TileSurface) -> Tokens { Tokens.make(self, surface) }
}

// MARK: - Tokens

public extension TileFinish {
    /// The numbers behind a finish, named so the owner's choice can be written into direction G as design tokens.
    ///
    /// Opacities are 0 to 1. A *sheen* is one vertical gradient (a white highlight at the top, a black shade at the
    /// bottom) so a tile draws one gradient layer, not two. A *rim* is a 1 pt hairline stroked with a vertical white
    /// gradient, lit at the top.
    struct Tokens: Equatable, Sendable {
        /// The dark underlay beneath a translucent fill or the off ground: `#1C1C1E` at this opacity (the thin module is
        /// 0.66). Lower lets more wallpaper through.
        public var underlay: Double
        /// The underlay beneath a translucent family fill: lower than ``underlay`` because a saturated fill hides more of
        /// the module, so the wallpaper can tint it without costing the white ink its 4.5:1.
        public var fillUnderlay: Double
        /// A white veil over the off ground (the web's `rgba(255,255,255,0.1)`).
        public var offVeil: Double
        /// The opacity of a white-ink family or room fill over the underlay; dark-ink fills (lights, power) stay opaque.
        public var fillOpacity: Double
        /// White at the top of the sheen.
        public var sheenTop: Double
        /// Black at the bottom of the sheen.
        public var sheenBottom: Double
        /// The sheen runs diagonally from the top-leading corner (the web's 135 degrees) instead of straight down.
        public var sheenDiagonal: Bool
        /// The tile's corner radius: 22 pt (``HassTokens/Radius/tile``), or the web's 28 pt for the web port.
        public var cornerRadius: Double
        /// The rim's white at the top edge, and at the bottom edge.
        public var rimTop: Double
        public var rimBottom: Double
        /// A thin line of the family colour round an on tile (B's edge glow), 0 for none.
        public var edgeGlow: Double
        /// A wash of the family colour from the top-leading corner on an on tile (B), 0 for none.
        public var edgeWash: Double

        static func make(_ finish: TileFinish, _ surface: TileSurface) -> Tokens {
            // A sheet has no wallpaper to show through, so a finish there is opaque: the same sheen and rim over the cell.
            let page = surface == .page
            switch finish {
            case .solid:
                return Tokens(underlay: 0.66, fillUnderlay: 0.66, offVeil: 0, fillOpacity: 1, sheenTop: 0.10, sheenBottom: 0, sheenDiagonal: false,
                              cornerRadius: 22,
                              rimTop: 0, rimBottom: 0, edgeGlow: 0, edgeWash: 0)
            case .tintedGlass:
                return Tokens(underlay: 0.66, fillUnderlay: 0.50, offVeil: 0, fillOpacity: page ? 0.78 : 1, sheenTop: 0.14,
                              sheenBottom: 0.08, sheenDiagonal: false, cornerRadius: 22, rimTop: 0.32, rimBottom: 0.06, edgeGlow: 0, edgeWash: 0)
            case .frostedModule:
                return Tokens(underlay: 0.66, fillUnderlay: 0.66, offVeil: 0, fillOpacity: 1, sheenTop: 0.10, sheenBottom: 0.06,
                              sheenDiagonal: false, cornerRadius: 22, rimTop: 0.22, rimBottom: 0.06, edgeGlow: 0.62, edgeWash: 0.26)
            case .webPort:
                return Tokens(underlay: page ? 0.62 : 0.42, fillUnderlay: 0.42, offVeil: page ? 0.05 : 0, fillOpacity: page ? 0.84 : 1, sheenTop: 0.15,
                              sheenBottom: 0.12, sheenDiagonal: true, cornerRadius: 28, rimTop: 0.24, rimBottom: 0.0, edgeGlow: 0, edgeWash: 0)
            }
        }
    }
}

// MARK: - Environment

public extension EnvironmentValues {
    /// The finish tiles inside are drawn with (``TileFinish``).
    @Entry var tileFinish: TileFinish = .standard
}

public extension View {
    /// Draws tiles inside with `finish`; the gallery uses it to compare the proposals on the same tiles.
    func tileFinish(_ finish: TileFinish) -> some View { environment(\.tileFinish, finish) }
}
