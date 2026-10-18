import SwiftUI

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
