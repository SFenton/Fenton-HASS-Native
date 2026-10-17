import SwiftUI

/// The web port's text shadow (`Card.module.css`: `text-shadow: 0 1px 2px rgba(0, 0, 0, 0.34)`), drawn on a page only.
struct FinishTextShadow: ViewModifier {
    var finish: TileFinish
    var surface: TileSurface

    func body(content: Content) -> some View {
        if finish == .webPort, surface == .page {
            content.shadow(color: .black.opacity(0.30), radius: 1, x: 0, y: 1)
        } else {
            content
        }
    }
}
