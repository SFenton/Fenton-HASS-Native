import SwiftUI

// MARK: - Window hinge

extension EnvironmentValues {
    /// The active vertical or horizontal division (iPhone Duo hinge in book pose) in window coordinates;
    /// nil on devices without one and while the inner display is flat (Festival owner #361: flat splits at
    /// the midpoint).
    @Entry var windowHinge: CGRect?
}

extension View {
    /// Reads the window's active division from a full-window probe and publishes it as
    /// ``SwiftUI/EnvironmentValues/windowHinge``.
    func readsWindowHinge() -> some View { modifier(WindowHingeReader()) }
}

/// Implementation of ``SwiftUI/View/readsWindowHinge()``.
private struct WindowHingeReader: ViewModifier {
    @State private var hinge: CGRect?

    func body(content: Content) -> some View {
        content
            .environment(\.windowHinge, hinge)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { hinge = Self.activeDivision(in: proxy) }
                        .onChange(of: proxy.size) { _, _ in hinge = Self.activeDivision(in: proxy) }
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
    }

    /// The first active division reported for a probe spanning the window (iOS 27.1 SDK only).
    @MainActor
    static func activeDivision(in proxy: GeometryProxy) -> CGRect? {
        #if os(iOS) && !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame).first
        }
        #endif
        return nil
    }
}
