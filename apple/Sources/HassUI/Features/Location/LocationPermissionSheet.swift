import HassDesign
import SwiftUI

/// ``LocationPermissionView`` for a ``LocationCoordinator``, as a page sheet: the after-sign-in offer and the Account
/// sheet's Share Location row present the same screen.
struct LocationPermissionSheet: View {
    var location: LocationCoordinator
    var onClose: () -> Void

    var body: some View {
        LocationPermissionView(
            permission: location.reporter.permission,
            canAskForAlways: !location.hasAskedForAlways,
            onRequestPermission: { location.requestPermission() },
            onClose: onClose
        )
        .hassSheet(.page)
    }
}
