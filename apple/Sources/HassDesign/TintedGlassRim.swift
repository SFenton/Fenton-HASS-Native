import SwiftUI

/// The hairline of a tinted glass tile: a 1 pt stroke lit at the top.
struct TintedGlassRim: View {
    var style: TileFaceStyle
    var surface: TileSurface
    var appearance: TileAppearance
    var cornerRadius = HassTokens.Radius.tile

    var body: some View {
        let tokens = TileFinish.Tokens.tintedGlass(on: surface)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // A white cell in a light sheet has no dark ground for a white hairline to lift off, so an off face there takes
        // the sheet's own separator colour.
        let onLightCell = appearance == .light && !style.isFilledOrLit
        Group {
            if TileFinish.omitted.contains("rim") {
                EmptyView()
            } else if onLightCell {
                shape.strokeBorder(HassTokens.Surface.separator, lineWidth: 1)
            } else {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(tokens.rimTop), .white.opacity(tokens.rimBottom)], startPoint: .top,
                                   endPoint: .bottom), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
