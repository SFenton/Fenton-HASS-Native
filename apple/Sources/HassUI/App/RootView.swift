import CoreSpotlight
import HassCore
import HassDesign
import HassTelemetry
import SwiftUI

/// The app's root: sign-in or the main tabs, plus scene-phase handling and the launch and arrival motion
/// (`.agents/design/direction-g.md`, "Launch and sign-in motion").
///
/// - A cold launch starts on the plain dark ground the launch screen shows (``SignInStyle/base``), which fades away in 0.2 s: onto
///   the sign-in intro when signed out, onto the disk snapshot when signed in (no intro and no spinner; live values then update in
///   place).
/// - A sign-in lifts the sign-in layer away while Home arrives under it (``HomeArrival``), about 0.9 s in all.
/// - A rejected token ends the session and shows the welcome back sign-in (``AppSession/sessionExpired()``).
public struct RootView: View {
    /// Owned by the app delegate: SwiftUI re-runs this initializer whenever the scene rebuilds, so a session made
    /// here (even through `State(initialValue:)`) would start a new connection each time.
    private let session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrival = HomeArrival()
    /// The plain ground over the first frame of a cold launch, until it fades.
    @State private var showsLaunchGround = true
    /// The sign-in layer stays in the tree while it lifts away after a sign-in.
    @State private var keepsSignIn = false
    /// The sign-in layer is lifting (the change that animates it).
    @State private var signInLeaves = false

    /// Creates the root.
    /// - Parameter session: The app's one session.
    public init(session: AppSession) {
        self.session = session
    }

    /// Opens the page of a tapped Spotlight result.
    private func openSpotlightResult(_ activity: NSUserActivity) {
        session.push.open(spotlightUserInfo: activity.userInfo)
    }

    /// Whether the sign-in intro plays: while the session has not played it (a cold launch, or the first screen after a sign-out). Debug launches can switch it off (`FENTON_SKIP_INTRO=1`) so a
    /// journey that is not about the intro does not wait for it.
    static func playsIntro(played: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        if environment["FENTON_SKIP_INTRO"] == "1" { return false }
        #endif
        return !played
    }

    public var body: some View {
        Group {
            if let gallery = ComponentGallery.requested {
                // Debug builds only: fixture-driven controls for UI tests and screenshots.
                ComponentGallery(page: gallery)
            } else {
                shell
            }
        }
        .observesDeviceSignals()
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
        // Launch cost runs (`FENTON_LAUNCHCOST=1`, any build): an invisible element a test reads the last measurement from.
        .overlay(alignment: .bottomTrailing) {
            if LaunchCostProbe.isEnabled { LaunchCostProbeElement() }
        }
        // The launch screen's ground, held over the first frame and faded out in 0.2 s.
        .overlay {
            if showsLaunchGround {
                Color(rgb: SignInStyle.base)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        // The user's appearance for sheets: the shell and the galleries force dark for their pages, which hides it
        // from their own environment (`SystemAppearance`).
        .publishesSystemAppearance()
        .environment(\.homeArrival, arrival)
        .environment(session.motion)
        .onAppear(perform: firstFrame)
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

    // MARK: Shell

    /// The signed-in tabs under the sign-in layer: the layer is present while signed out and while it lifts away.
    private var shell: some View {
        ZStack {
            if case let .signedIn(connection, _) = session.phase {
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
                    .onChange(of: connection.status) { _, status in session.connectionStatusChanged(status) }
                    .transition(.identity)
            }
            if !session.isSignedIn || keepsSignIn {
                LoginView(
                    model: LoginModel(mode: session.expiredAccount.map { .welcomeBack($0) } ?? .fresh),
                    playsIntro: Self.playsIntro(played: session.motion.hasPlayed(.intro)),
                    onIntroPlayed: { session.motion.markPlayed(.intro) },
                    onUseDifferentAccount: { session.forgetExpiredAccount() },
                    onSignedIn: signedIn
                )
                .offset(y: signInLeaves && !reduceMotion ? MotionTokens.Arrival.liftDistance : 0)
                .scaleEffect(signInLeaves && !reduceMotion ? MotionTokens.Arrival.liftScale : 1)
                .opacity(signInLeaves ? 0 : 1)
                .allowsHitTesting(!session.isSignedIn)
                .accessibilityHidden(session.isSignedIn)
                .transition(.opacity)
            }
        }
        .animation(MotionTokens.crossFade, value: session.isSignedIn)
    }

    // MARK: Motion

    /// The first frame is up: end the launch interval and let the launch ground go.
    private func firstFrame() {
        Task { @MainActor in
            await Task.yield()
            Telemetry.endTracked(Telemetry.Name.launch)
            // Signed out there is no snapshot to show.
            if !session.isSignedIn { Telemetry.cancelTracked(Telemetry.Name.snapshotShown) }
            withAnimation(MotionTokens.quick) { showsLaunchGround = false }
            // The intro (signed out) or the snapshot (signed in) is on screen now: that is what a launch cost run measures.
            if LaunchCostProbe.isEnabled { Task { await LaunchCostProbe.measureWindow(session.isSignedIn ? "snapshot" : "intro") } }
        }
    }

    /// Tokens arrived: hold Home's elements back, start the session under the sign-in layer, then lift the layer away while
    /// the backdrop settles and the header, chips, cards and tab bar come in (about 0.9 s; Reduce Motion cross-fades).
    private func signedIn(_ server: HassServer, _ tokens: AuthTokens) throws {
        Telemetry.cancelTracked(Telemetry.Name.snapshotShown)
        // The arrival plays once per session (reset at sign-out); any other sign-in just swaps the screens.
        guard !session.motion.hasPlayed(.signInArrival) else {
            Telemetry.cancelTracked(Telemetry.Name.arrival)
            try session.didSignIn(server: server, tokens: tokens)
            return
        }
        // Building Home behind the sign-in layer is one long turn of its own; the arrival motion is measured after it.
        LaunchCostProbe.begin("arrival-build")
        arrival.begin()
        keepsSignIn = true
        signInLeaves = false
        do {
            try session.didSignIn(server: server, tokens: tokens)
        } catch {
            arrival.finish()
            keepsSignIn = false
            throw error
        }
        session.motion.markPlayed(.signInArrival)
        Task {
            // Home's views are built, held back; now they and the layer move.
            try? await Task.sleep(for: .milliseconds(60))
            LaunchCostProbe.finish()
            LaunchCostProbe.begin("arrival")
            withAnimation(reduceMotion ? MotionTokens.crossFade : MotionTokens.Arrival.lift) { signInLeaves = true }
            arrival.reveal()
            try? await Task.sleep(for: .milliseconds(400))
            keepsSignIn = false
            signInLeaves = false
            try? await Task.sleep(for: HomeArrival.duration - .milliseconds(460))
            arrival.finish()
            Telemetry.endTracked(Telemetry.Name.arrival)
            LaunchCostProbe.finish()
        }
    }
}
