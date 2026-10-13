import SwiftUI

// MARK: - Window hinge

extension EnvironmentValues {
    /// The iPhone Duo hinge in window coordinates: the active fold while the inner display is partly
    /// folded, else the hinge the system reports while it lies flat. Nil on devices without one and on
    /// the folded Duo's outer display. On-demand splits put their divider here (FestivalNativeApps
    /// `DeviceLayout.splitHinge`; owner rule for this app, 2026-10-10: "on the hinge on the Duo").
    @Entry var windowHinge: CGRect?
}

extension View {
    /// Reads the window's hinge from a full-window probe and publishes it as
    /// ``SwiftUI/EnvironmentValues/windowHinge``.
    func readsWindowHinge() -> some View { modifier(WindowHingeReader()) }
}

/// Implementation of ``SwiftUI/View/readsWindowHinge()``.
///
/// Reads in `onGeometryChange`, which runs again whenever the probe's geometry (reserved regions
/// included) changes. Reading only on appear and on size changes missed the regions: they arrive after
/// the first layout, and a fold or unfold need not change the window size.
private struct WindowHingeReader: ViewModifier {
    @State private var hinge: CGRect?

    func body(content: Content) -> some View {
        content
            .environment(\.windowHinge, hinge)
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGRect?.self, of: Self.hinge(in:)) { hinge = $0 }
                    .accessibilityHidden(true)
            }
    }

    /// The active division, else any division (`.includeInactive`: the hinge while flat), for a probe
    /// spanning the window. iOS 27.1 SDK only; nil elsewhere.
    nonisolated static func hinge(in proxy: GeometryProxy) -> CGRect? {
        #if os(iOS) && !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) {
            if let active = proxy.reservedRegions(kind: .division).first(where: \.isActive) {
                return active.frame
            }
            return proxy.reservedRegions(kind: .division, options: [.includeInactive]).first?.frame
        }
        #endif
        return nil
    }
}
