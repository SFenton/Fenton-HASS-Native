import HassCore
import HassDesign
import SwiftUI

/// Presents the location permission screen when ``LocationCoordinator`` offers it, and sends a fix each time the
/// app comes to the foreground (`.agents/pages/settings/location.md`).
struct LocationPermissionPresenter: ViewModifier {
    @Bindable var location: LocationCoordinator
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $location.isPresentingPermission) {
                LocationPermissionView(
                    permission: location.reporter.permission,
                    canAskForAlways: !location.hasAskedForAlways,
                    onRequestPermission: { location.requestPermission() },
                    onClose: { location.isPresentingPermission = false }
                )
                .hassSheet(.page)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await location.didBecomeActive() }
            }
    }
}

extension View {
    /// Location's permission screen and foreground fixes, when this launch reports location.
    @ViewBuilder
    func locationReporting(_ location: LocationCoordinator?) -> some View {
        if let location {
            modifier(LocationPermissionPresenter(location: location))
        } else {
            self
        }
    }
}
