import SwiftUI

/// The ground of a tile under one of the frosted finishes (``TileFinish``): layers of translucency, one sheen gradient and
/// the family colour, never a live blur. ``GlassTileFace`` uses it instead of its solid ground whenever the effective finish
/// is not ``TileFinish/solid``.
struct FrostedGround: View {
    var finish: TileFinish
    var style: TileFaceStyle
    var surface: TileSurface
    var appearance: TileAppearance
    /// The caller's tint, for a tinted face's progress band.
    var tint: Color
    var wash: Color?
    var level: Double?
    var levelTint: Color?

    private var tokens: TileFinish.Tokens { finish.tokens(on: surface) }

    var body: some View {
        let tokens = tokens
        ZStack(alignment: .leading) {
            switch style {
            case .off, .tinted, .error:
                neutral(dense: style == .error, tokens: tokens)
                if let wash { wash.opacity(appearance.washOpacity) }
                band { (levelTint ?? tint).opacity(0.32) }
            case .lit where finish.usesGlyphDisc:
                // B keeps the module neutral; the lit tile's warmth is the disc and the edge.
                neutral(dense: false, tokens: tokens)
                edge(Color(rgb: appearance == .light ? 0xBD6F24 : 0xFF9630), tokens)
            case .lit:
                // Dark ink on a light fill: lights and power stay opaque, because a translucent light fill over the dark
                // wallpaper only gets darker.
                LitTile.base
                band(default: 1) {
                    LinearGradient(colors: [LitTile.bandTop, LitTile.bandBottom], startPoint: .top, endPoint: .bottom)
                        .overlay { if let levelTint { levelTint.opacity(LitTile.bulbTint) } }
                }
            case let .colored(rgb):
                if finish.usesGlyphDisc { neutral(dense: false, tokens: tokens); edge(Self.edgeColor(forFill: rgb), tokens) }
                else { tinted(rgb, tokens) }
            case let .filled(family):
                if finish.usesGlyphDisc {
                    neutral(dense: false, tokens: tokens)
                    edge(Color(rgb: appearance == .light ? family.glyphLightRGB : family.spec.glyph), tokens)
                } else if family.spec.darkInk {
                    LinearGradient(colors: [LitTile.powerTop, family.fill ?? .yellow], startPoint: .top, endPoint: .bottom)
                } else {
                    tinted(family.spec.fill ?? 0, tokens)
                }
                if let level, level > 0 {
                    if family.spec.darkInk {
                        band { Color.white.opacity(TileFaceStyle.progressLighten) }
                    } else {
                        GeometryReader { proxy in
                            Color.black.opacity(TileFaceStyle.progressShade)
                                .frame(width: proxy.size.width * (1 - min(1, level)))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            sheen(tokens)
        }
    }

    // MARK: Layers

    /// The neutral frosted module: the dark underlay, then a milky white veil on the page; the sheet's cell in a sheet.
    @ViewBuilder
    private func neutral(dense: Bool, tokens: TileFinish.Tokens) -> some View {
        switch surface {
        case .sheet:
            HassTokens.Surface.sheetCell
        case .page:
            if dense {
                // An error keeps the dense module, so its red state text holds 4.5:1 over the lit windows.
                Color(rgb: HassTokens.Palette.moduleDense).opacity(0.78)
            } else {
                // The underlay and the veil as one colour: the same pixels as two layers, one layer fewer per tile.
                FinishColor.flatten([(HassTokens.Palette.moduleThin, tokens.underlay), (0xFFFFFF, tokens.offVeil)])
            }
        }
    }

    /// A white-ink fill: the family colour over the dark underlay at the finish's opacity (opaque in a sheet).
    @ViewBuilder
    private func tinted(_ fill: UInt32, _ tokens: TileFinish.Tokens) -> some View {
        if surface == .page, tokens.fillOpacity < 1 {
            FinishColor.flatten([(HassTokens.Palette.moduleThin, tokens.fillUnderlay), (fill, tokens.fillOpacity)])
        } else {
            Color(rgb: fill)
        }
    }

    /// B's lit edge: a wash of the family colour from the top-leading corner. (The coloured hairline is ``FrostedRim``.)
    @ViewBuilder
    private func edge(_ colour: Color, _ tokens: TileFinish.Tokens) -> some View {
        if tokens.edgeWash > 0 {
            LinearGradient(colors: [colour.opacity(tokens.edgeWash), colour.opacity(0)], startPoint: .topLeading,
                           endPoint: UnitPoint(x: 0.75, y: 0.8))
        }
    }

    /// The one sheen gradient: a white highlight at the top fading through clear to a black shade at the bottom (the web's
    /// `::after` pair of gradients, merged so a tile draws one layer).
    @ViewBuilder
    private func sheen(_ tokens: TileFinish.Tokens) -> some View {
        // A white cell in a light sheet has nothing for a highlight or a shade to work on: the rim alone finishes it.
        let bareLightCell = surface == .sheet && appearance == .light && (finish.usesGlyphDisc || !style.isFilledOrLit)
        if !bareLightCell, !TileFinish.omitted.contains("sheen"), tokens.sheenTop > 0 || tokens.sheenBottom > 0 {
            LinearGradient(
                stops: [.init(color: .white.opacity(tokens.sheenTop), location: 0), .init(color: .clear, location: 0.46),
                        .init(color: .black.opacity(tokens.sheenBottom), location: 1)],
                startPoint: tokens.sheenDiagonal ? .topLeading : .top,
                endPoint: tokens.sheenDiagonal ? UnitPoint(x: 0.8, y: 1) : .bottom)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func band(default fallback: Double? = nil, @ViewBuilder fill: () -> some View) -> some View {
        if let level = level ?? fallback, level > 0 {
            let band = fill()
            GeometryReader { proxy in
                band.frame(width: proxy.size.width * min(1, level))
            }
        }
    }

    /// A room's fill lightened for use as an edge line on the dark frosted module.
    static func edgeColor(forFill rgb: UInt32) -> Color {
        Color(rgb: ColorFamily.mix(0xFFFFFF, rgb, 0.38))
    }
}
