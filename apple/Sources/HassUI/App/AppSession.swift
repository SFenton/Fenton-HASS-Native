import Foundation
import HassCore
import HassTelemetry
import Observation

/// Signed-in state for the whole app.
@MainActor
@Observable
public final class AppSession {
    /// Where the app is.
    public enum Phase {
        case signedOut
        case signedIn(HassConnection, ConnectionLifecycle)
    }

    /// Current phase.
    public private(set) var phase: Phase = .signedOut

    /// Opens the launch intervals (`Telemetry.beginTracked`): the app calls it as early as it can, from its `App` initializer, so the
    /// first frame and the snapshot are timed from process start rather than from the first view.
    public nonisolated static func beginLaunchMeasurement() {
        Telemetry.beginTracked(Telemetry.Name.launch)
        Telemetry.beginTracked(Telemetry.Name.snapshotShown)
    }

    /// Whether a session is running (the phase is ``Phase/signedIn(_:_:)``).
    public var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    /// Who was signed in when the session ended because Home Assistant rejected the refresh token, so sign-in can say
    /// "Welcome back, Stephen" and ask for the password alone. Nil after a deliberate sign-out, a fresh install, or Use a
    /// Different Account.
    public private(set) var expiredAccount: RememberedAccount?

    /// The blurred house photo behind every page, for the signed-in server (``HouseBackdrop``).
    @ObservationIgnored private(set) var backdrop: HouseBackdropStore?

    /// Token source for the signed-in server, used by the Home Assistant settings web view.
    @ObservationIgnored public private(set) var tokens: TokenManager?

    /// Native notifications: registration with Home Assistant and what a notification opens.
    @ObservationIgnored public let push: PushCoordinator

    /// Location reporting in shadow mode; nil on iPad and in launches that don't report (``LocationLaunchPolicy``).
    @ObservationIgnored public let location: LocationCoordinator?

    /// The Live Activities: tokens for Home Assistant, button presses and sign-out (nil in tests that do not need it).
    @ObservationIgnored public let liveActivities: LiveActivityCoordinator?

    /// Which one-time moments (intro, sign-in arrival) have played, and Reduce Motion. One per session; reset at sign-out
    /// (`.agents/design/motion.md`). `RootView` puts it in the environment.
    public let motion: MotionPolicy

    /// The app's pages in system search; filled when a session starts and emptied at sign-out.
    @ObservationIgnored private let spotlight: any SpotlightIndexing

    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache
    @ObservationIgnored private let remembered: RememberedAccountStore

    /// Creates the session, resuming a saved sign-in if one exists. Restoring is synchronous and
    /// network-free, so the first frame already shows the cached Home screen.
    /// - Parameters:
    ///   - tokenStore: Where the refresh token lives; shared with the notification service extension.
    ///   - snapshotCache: The disk snapshot of entity states.
    ///   - push: The app's push coordinator (the app delegate's, so system callbacks reach it).
    ///   - location: The app's location coordinator (the app delegate's, created at launch for zone relaunches).
    ///   - liveActivities: The app's Live Activity coordinator (the app delegate's, so its buttons work at launch).
    ///   - spotlight: Where the app's pages are indexed; inert unless the app passes ``CoreSpotlightIndexer``.
    ///   - motion: The session's motion policy; tests inject one with a fake Reduce Motion source.
    ///   - remembered: Where the last username and the person's name are kept (``expiredAccount``).
    public init(tokenStore: TokenStore = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup),
                snapshotCache: EntitySnapshotCache = .init(), push: PushCoordinator = .inert(),
                location: LocationCoordinator? = nil, liveActivities: LiveActivityCoordinator? = nil,
                spotlight: any SpotlightIndexing = InertSpotlightIndexer(),
                motion: MotionPolicy = MotionPolicy(),
                remembered: RememberedAccountStore = RememberedAccountStore()) {
        self.spotlight = spotlight
        self.motion = motion
        self.remembered = remembered
        self.tokenStore = tokenStore
        self.snapshotCache = snapshotCache
        self.push = push
        self.location = location
        self.liveActivities = liveActivities
        #if DEBUG
        // UI tests start signed out: FENTON_UITEST_RESET=1 clears the saved sign-in and snapshot, and the location
        // screen is offered again.
        if ProcessInfo.processInfo.environment["FENTON_UITEST_RESET"] == "1" {
            tokenStore.clear()
            snapshotCache.clear()
            LocationCoordinator.resetOffers()
            remembered.forget()
        }
        // FENTON_EXPIRED_ACCOUNT=<username>|<name> starts signed out as if that account's session had just ended, so
        // journeys can look at the welcome back sign-in.
        if let value = ProcessInfo.processInfo.environment["FENTON_EXPIRED_ACCOUNT"], tokenStore.load() == nil {
            let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            expiredAccount = RememberedAccount(username: parts[0], name: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
        }
        // FENTON_HASS_TOKEN signs in with a long-lived access token for this launch only (never saved),
        // so journeys can run against the real server without a password.
        if let token = ProcessInfo.processInfo.environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let server = ProcessInfo.processInfo.environment["FENTON_HASS_SERVER"]
                .flatMap(URL.init(string:)).map(HassServer.init(baseURL:)) ?? .fentonHome
            let tokens = AuthTokens(accessToken: token, expiresAt: .distantFuture, refreshToken: "")
            motion.markPlayed(.signInArrival)
            start(server: server, tokens: TokenManager(store: InMemoryTokenStore(), initial: tokens))
            return
        }
        #endif
        if let stored = tokenStore.load() {
            // Resuming a saved sign-in is not an arrival: nothing introduces the app to someone already in it.
            motion.markPlayed(.signInArrival)
            start(server: stored.server, tokens: TokenManager(store: tokenStore))
        }
    }

    /// Completes sign-in with fresh tokens.
    public func didSignIn(server: HassServer, tokens: AuthTokens) throws {
        try tokenStore.save(StoredCredentials(server: server, refreshToken: tokens.refreshToken))
        expiredAccount = nil
        start(server: server, tokens: TokenManager(store: tokenStore, initial: tokens))
    }

    /// Ends the session because Home Assistant rejected the token, and keeps who it was for the sign-in's welcome back (a
    /// silent blank form told the person nothing). With no remembered username (a phone signed in before the app kept one)
    /// the plain sign-in shows.
    public func sessionExpired() {
        let account = remembered.account
        signOut()
        expiredAccount = account
    }

    /// Reacts to the connection's status: a refused token ends the session (``sessionExpired()``); every other status
    /// is the connection's own business.
    public func connectionStatusChanged(_ status: HassConnection.Status) {
        if status == .rejected { sessionExpired() }
    }

    /// Forgets the account a rejected session left behind (Use a Different Account): the next sign-in asks for a username.
    public func forgetExpiredAccount() {
        remembered.forget()
        expiredAccount = nil
    }

    /// Why a confirmed sign-out stayed signed in.
    public struct SignOutFailure: Error, Equatable {}

    /// Signs out only once Home Assistant confirms this phone is off the user's person (already off counts). Any
    /// failure throws and leaves the session signed in, so the caller shows its alert and the person can retry.
    /// Debug builds take `FENTON_SIGNOUT_FAIL=1` to fail without a server (journeys).
    public func confirmedSignOut() async throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_SIGNOUT_FAIL"] == "1" { throw SignOutFailure() }
        #endif
        if case let .signedIn(connection, _) = phase, location != nil {
            do {
                let user = try await connection.currentUser()
                try await push.mobileApp.unlinkPresence(user: user, api: connection)
            } catch {
                throw SignOutFailure()
            }
        }
        signOut()
    }

    /// Signs out: stops pushes to this phone, then revokes the refresh token; clears the Keychain, cache and
    /// store. Home Assistant gets the empty push registration before the token is revoked (contract v1, rule 2).
    public func signOut() {
        if case let .signedIn(connection, _) = phase {
            connection.disconnect()
            connection.store.reset()
        }
        let stored = tokenStore.load()
        tokenStore.clear()
        snapshotCache.clear()
        TodoItemsCache().clear()
        WeatherForecastDiskCache().clear()
        UserDefaults.standard.removeObject(forKey: ChoresModel.viewerDefaultsKey)
        tokens = nil
        backdrop = nil
        motion.reset()
        spotlight.removeAll()
        // A second sign-in plays its arrival again, and the signed-out screen its intro.
        motion.reset()
        phase = .signedOut
        let push = push, liveActivities = liveActivities
        Task {
            // Nothing of the signed-in person stays on a Lock Screen.
            await liveActivities?.sessionEnded()
            await push.sessionEnded()
            await AppIconBadgeSync.shared.clear()
            if let stored { await HassLoginFlow.revoke(server: stored.server, refreshToken: stored.refreshToken) }
        }
    }

    private func start(server: HassServer, tokens: TokenManager) {
        // At home the socket uses Home Assistant's home network address instead of the public URL (LocalServerRoute).
        let route = LocalServerRoute.isEnabled() ? LocalServerRoute(server: server) : nil
        let connection = HassConnection(server: server, tokens: tokens, store: EntityStore(), snapshotCache: snapshotCache, route: route)
        let lifecycle = ConnectionLifecycle(connection: connection)
        self.tokens = tokens
        push.sessionStarted(server: server) { try await tokens.validAccessToken() }
        liveActivities?.sessionStarted()
        // Created before the phase changes so the first signed-in frame already has the cached photo.
        backdrop = HouseBackdropStore.session(for: server)
        phase = .signedIn(connection, lifecycle)
        spotlight.indexPages(SpotlightCatalog.entries)
        lifecycle.didBecomeActive()
    }
}
