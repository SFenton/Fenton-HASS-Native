import SwiftUI

/// The one sheen gradient of tinted glass: a white highlight at the top fading through clear to a black shade at the bottom
/// (the web's `::after` pair of gradients, merged so a tile draws one layer). Left out in a Debug launch with
/// `FENTON_TILE_FINISH_OMIT=sheen` (performance.md).
struct TintedGlassSheen: View {
    var tokens: TileFinish.Tokens
    /// Whether the white highlight is drawn; false leaves only the bottom shade.
    var highlight = true

    var body: some View {
        if !TileFinish.omitted.contains("sheen") {
            LinearGradient(
                stops: [.init(color: .white.opacity(highlight ? tokens.sheenTop : 0), location: 0),
                        .init(color: .clear, location: TileFinish.Tokens.sheenClearStop),
                        .init(color: .black.opacity(tokens.sheenBottom), location: 1)],
                startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
    }
}

/// Gives a filled control tinted glass's edge: the sheen over its fill and the lit hairline round it. For selection
/// controls that are not a ``GlassTile`` (the alarm mode buttons), so a chosen option reads as the same material as a tile.
private struct TintedGlassEdge: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.tileFinish) private var preferredFinish
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let finish = TileFinish.effective(preferredFinish, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
        if finish == .solid {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .overlay { TintedGlassSheen(tokens: .tintedGlass(on: .sheet)).clipShape(shape) }
                .overlay { TintedGlassRim(style: .colored(0), surface: .sheet, appearance: .dark, cornerRadius: cornerRadius) }
        }
    }
}

public extension View {
    /// Draws tinted glass's sheen and lit hairline over this opaque filled control (``TileFinish``): nothing with Reduce
    /// Transparency or Increase Contrast. The control keeps its own fill and ink.
    /// - Parameter cornerRadius: The control's corner radius.
    func tintedGlassEdge(cornerRadius: CGFloat) -> some View { modifier(TintedGlassEdge(cornerRadius: cornerRadius)) }
}
