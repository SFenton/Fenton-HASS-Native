import SwiftUI

/// The hairline of a frosted tile: a 1 pt stroke lit at the top, plus B's coloured edge.
struct FrostedRim: View {
    var finish: TileFinish
    var style: TileFaceStyle
    var surface: TileSurface
    var appearance: TileAppearance

    var body: some View {
        let tokens = finish.tokens(on: surface)
        let shape = RoundedRectangle(cornerRadius: tokens.cornerRadius, style: .continuous)
        // A white cell in a light sheet has no dark ground for a white hairline to lift off, so an off face there takes
        // the sheet's own separator colour.
        let onLightCell = appearance == .light && (finish.usesGlyphDisc || !style.isFilledOrLit)
        ZStack {
            if TileFinish.omitted.contains("rim") {
                EmptyView()
            } else if onLightCell {
                shape.strokeBorder(HassTokens.Surface.separator, lineWidth: 1)
            } else {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(tokens.rimTop), .white.opacity(tokens.rimBottom)], startPoint: .top,
                                   endPoint: .bottom), lineWidth: 1)
            }
            if tokens.edgeGlow > 0, let colour = glowColour {
                shape.strokeBorder(colour.opacity(tokens.edgeGlow), lineWidth: 1.25)
            }
        }
        .allowsHitTesting(false)
    }

    /// B's edge colour: the family's glyph colour, a room's lightened fill, the lit tile's amber, or the error red.
    private var glowColour: Color? {
        switch style {
        case let .filled(family): Color(rgb: appearance == .light ? family.glyphLightRGB : family.spec.glyph)
        case let .colored(rgb): appearance == .light ? Color(rgb: rgb) : FrostedGround.edgeColor(forFill: rgb)
        case .lit: Color(rgb: appearance == .light ? 0xBD6F24 : 0xFF9630)
        case .error: Color(rgb: appearance.errorRGB)
        case .off, .tinted: nil
        }
    }
}
