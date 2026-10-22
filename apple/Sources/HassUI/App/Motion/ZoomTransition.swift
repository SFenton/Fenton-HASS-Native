import HassDesign
import SwiftUI

public extension View {
    /// Marks this view as what a zoom transition grows out of (iOS 18 and later; on iOS 17 it does nothing and the push or
    /// sheet stays as it is). Use it only on a tile that *is* the thing it opens: a room tile, a camera card, a recipe card
    /// (design: `.agents/design/motion.md` §4.3). Never on a device tile that opens a control sheet.
    ///
    /// The source's corner radius is set to match the tile, so the morph is clean.
    /// - Parameters:
    ///   - id: What the destination names in ``zoomDestination(id:in:)``.
    ///   - namespace: Shared with the destination; declare it with `@Namespace` in the view that owns both.
    ///   - cornerRadius: The tile's radius. The default is the module radius, 26 pt.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID, cornerRadius: CGFloat = HassTokens.Radius.module) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Makes this the page a zoom grows into (iOS 18 and later; iOS 17 keeps the plain push). Apply it to the destination of
    /// the matching ``zoomSource(id:in:cornerRadius:)``, outside the page's own chrome. The page's transitions are recorded as
    /// `ZoomOpen` and `ZoomClose`.
    @ViewBuilder
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
                .environment(\.navigationKind, .zoom)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
