import SwiftUI

public extension View {
    /// Draws this navigation control on Liquid Glass in `shape`: the bottom section bar, toolbar circles and the
    /// Quick Links circle (`.agents/design/direction-g.md`, Layers). iOS 17–25 fall back to a thin-material
    /// capsule. Never use it for content on the page; that is ``SwiftUICore/View/module(_:cornerRadius:)``
    /// (HIG: Materials, Liquid Glass: "Use Liquid Glass for the navigation layer").
    /// - Parameter shape: The glass's outline, usually a `Capsule` or `Circle`.
    func navigationGlass(in shape: some Shape = Capsule()) -> some View {
        modifier(NavigationGlass(shape: shape))
    }
}

/// Implementation of ``SwiftUICore/View/navigationGlass(in:)``.
private struct NavigationGlass<S: Shape>: ViewModifier {
    var shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
