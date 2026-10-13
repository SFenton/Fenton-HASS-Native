import HassCore
import HassDesign
import SwiftUI

/// The app's root: sign-in or the main tabs, plus scene-phase handling.
public struct RootView: View {
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

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
