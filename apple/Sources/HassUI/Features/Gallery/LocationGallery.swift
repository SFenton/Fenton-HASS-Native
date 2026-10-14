#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the location permission screen: presents it as the app will, over a plain page, starting at
/// one permission stage. Continue plays the system's answer (While Using, then Always) so journeys can walk the
/// steps; Open Settings and Close are recorded on the `Last action` line.
///
/// Environment (optional): `FENTON_GALLERY_LOCATION=not-determined|when-in-use|always|denied|reduced-accuracy`
/// (default `not-determined`).
struct LocationGallery: View {
    @State private var permission: LocationPermission
    @State private var lastAction = "none"

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let stage = environment["FENTON_GALLERY_LOCATION"].flatMap(LocationPermission.Stage.init(rawValue:)) ?? .notDetermined
        _permission = State(initialValue: Self.permission(for: stage))
    }

    var body: some View {
        Text("Settings")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(HassTokens.Spacing.xl)
            .sheet(isPresented: .constant(true)) {
                LocationPermissionView(
                    permission: permission,
                    onRequestPermission: { answer() },
                    onOpenSettings: { lastAction = "open settings" },
                    onClose: { lastAction = "close" }
                ) {
                    if !GalleryEnvironment.isClean {
                        GalleryLastCall(text: lastAction, title: "Last action")
                            .padding(.horizontal, HassTokens.Spacing.xl)
                            .padding(.bottom, HassTokens.Spacing.s)
                    }
                }
                .hassSheet(.form)
            }
    }

    /// What iOS answers to the request at each step, as if the person chose the highlighted option.
    private func answer() {
        lastAction = "request \(permission.stage.rawValue)"
        permission = Self.answer(to: permission)
    }

    /// The permission after the person picks the highlighted option in the alert `permission` leads to.
    static func answer(to permission: LocationPermission) -> LocationPermission {
        switch permission.authorization {
        case .notDetermined: LocationPermission(authorization: .whenInUse)
        case .whenInUse: LocationPermission(authorization: .always)
        case .always, .denied, .restricted: permission
        }
    }

    /// The permission that shows `stage`.
    static func permission(for stage: LocationPermission.Stage) -> LocationPermission {
        switch stage {
        case .notDetermined: .notDetermined
        case .whenInUse: LocationPermission(authorization: .whenInUse)
        case .always: LocationPermission(authorization: .always)
        case .denied: LocationPermission(authorization: .denied)
        case .reducedAccuracy: LocationPermission(authorization: .always, isPrecise: false)
        }
    }
}
#endif
