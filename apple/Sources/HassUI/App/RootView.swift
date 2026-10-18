import CoreSpotlight
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

    /// Opens the page of a tapped Spotlight result.
    private func openSpotlightResult(_ activity: NSUserActivity) {
        session.push.open(spotlightUserInfo: activity.userInfo)
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
        // The session's motion policy, for the intro, the arrival and anything that plays once (`.arrivalMotion`).
        .environment(session.motion)
        // A tap on the Home Live Activity opens the focused job's page (`ActivityDeepLink`).
        .onOpenURL { session.push.openLiveActivity($0) }
        // A tapped Spotlight result (`SpotlightCatalog`): opens that page like a notification's link.
        .onContinueUserActivity(CSSearchableItemActionType, perform: openSpotlightResult)
        #if DEBUG
        // Journeys cannot tap a Spotlight result inside the app: `FENTON_OPEN_SPOTLIGHT=<item id>` hands the same
        // activity the system would to the same handler.
        .task {
            guard let identifier = ProcessInfo.processInfo.environment["FENTON_OPEN_SPOTLIGHT"] else { return }
            let activity = NSUserActivity(activityType: CSSearchableItemActionType)
            activity.userInfo = [CSSearchableItemActivityIdentifier: identifier]
            openSpotlightResult(activity)
        }
        #endif
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if ResourceCensusProbe.isEnabled { ResourceCensusProbe() }
        }
        #endif
        // Scroll cost runs (`FENTON_SCROLLCOST=1`, any build): an invisible element a test or `tools/ios_perf.sh` drives.
        .overlay(alignment: .topTrailing) {
            if ScrollCostProbe.isEnabled { ScrollCostProbe() }
        }
        // Navigation cost runs (`FENTON_NAVPERF=1`): an invisible element `NavigationPerformanceTests` reads after it drives the app.
        .overlay(alignment: .topLeading) {
            if NavigationPerfProbe.isEnabled { NavigationPerfProbe() }
        }
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
