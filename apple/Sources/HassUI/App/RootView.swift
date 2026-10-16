import HassCore
import HassDesign
import SwiftUI

/// The app's root: sign-in or the main tabs, plus scene-phase handling.
public struct RootView: View {
    /// Owned by the app delegate: SwiftUI re-runs this initializer whenever the scene rebuilds, so a session made
    /// here (even through `State(initialValue:)`) would start a new connection each time.
    private let session: AppSession
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the root.
    /// - Parameter session: The app's one session.
    public init(session: AppSession) {
        self.session = session
    }

    public var body: some View {
        Group {
            if let gallery = ComponentGallery.requested {
                // Debug builds only: fixture-driven controls for UI tests and screenshots.
                ComponentGallery(page: gallery)
            } else {
                switch session.phase {
                case .signedOut:
                    LoginView { server, tokens in try session.didSignIn(server: server, tokens: tokens) }
                case let .signedIn(connection, _):
                    MainTabView()
                        .environment(connection)
                        .environment(connection.store)
                        .environment(session)
                        .environment(session.push)
                        .environment(session.location)
                        .locationReporting(session.location)
                        .environment(session.backdrop)
                        .task { await session.backdrop?.refresh() }
                        .readsWindowHinge()
                        .onChange(of: connection.status) { _, status in
                            if status == .rejected { session.signOut() }
                        }
                }
            }
        }
        .observesDeviceSignals()
        // The user's appearance for sheets: the shell and the galleries force dark for their pages, which hides it
        // from their own environment (`SystemAppearance`).
        .publishesSystemAppearance()
        .task {
            // Telemetry (`.agents/patterns/telemetry.md`): MetricKit's daily reports, and the image cache kept
            // under its disk budget.
            MetricKitCollector.shared.start()
            await Task.detached(priority: .background) { ImagePipeline.shared.trimDisk() }.value
        }
        .onChange(of: scenePhase) { _, phase in
            guard case let .signedIn(_, lifecycle) = session.phase else { return }
            switch phase {
            case .active: lifecycle.didBecomeActive()
            case .background: lifecycle.didEnterBackground()
            default: break
            }
        }
    }
}
