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
/// (default `not-determined`), or `when-in-use-asked`: While Using after the Always alert was shown once.
struct LocationGallery: View {
    @State private var permission: LocationPermission
    @State private var canAskForAlways: Bool
    @State private var lastAction = "none"

    /// The extra gallery stage: While Using after iOS showed its one Always alert.
    static let askedStage = "when-in-use-asked"

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let requested = environment["FENTON_GALLERY_LOCATION"]
        let asked = requested == Self.askedStage
        let stage = asked ? .whenInUse : requested.flatMap(LocationPermission.Stage.init(rawValue:)) ?? .notDetermined
        _permission = State(initialValue: Self.permission(for: stage))
        _canAskForAlways = State(initialValue: !asked)
    }

    var body: some View {
        // A blank presenting page: text beside the iPad landscape page sheet is hidden from VoiceOver by the modal,
        // and the audit reports it as potentially inaccessible (2026-10-14).
        Color.black
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .sheet(isPresented: .constant(true)) {
                LocationPermissionView(
                    permission: permission,
                    canAskForAlways: canAskForAlways,
                    onRequestPermission: { answer() },
                    onOpenSettings: { lastAction = "open settings" },
                    onClose: { lastAction = "close" }
                ) {
                    if !GalleryEnvironment.isClean {
                        GalleryLastCall(text: lastAction, title: "Last action")
                    }
                }
                .hassSheet(.page)
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
