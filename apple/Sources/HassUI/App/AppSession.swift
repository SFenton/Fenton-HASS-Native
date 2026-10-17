import Foundation
import HassCore
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

    /// The blurred house photo behind every page, for the signed-in server (``HouseBackdrop``).
    @ObservationIgnored private(set) var backdrop: HouseBackdropStore?

    /// Token source for the signed-in server, used by the Home Assistant settings web view.
    @ObservationIgnored public private(set) var tokens: TokenManager?

    /// Native notifications: registration with Home Assistant and what a notification opens.
    @ObservationIgnored public let push: PushCoordinator

    /// Location reporting in shadow mode; nil on iPad and in launches that don't report (``LocationLaunchPolicy``).
    @ObservationIgnored public let location: LocationCoordinator?

    /// The Home Live Activity: tokens for Home Assistant and the foreground start (nil in tests that don't need it).
    @ObservationIgnored public let liveActivities: LiveActivityCoordinator?

    /// The app's pages in system search; filled when a session starts and emptied at sign-out.
    @ObservationIgnored private let spotlight: any SpotlightIndexing

    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache

    /// Creates the session, resuming a saved sign-in if one exists. Restoring is synchronous and
    /// network-free, so the first frame already shows the cached Home screen.
    /// - Parameters:
    ///   - tokenStore: Where the refresh token lives; shared with the notification service extension.
    ///   - snapshotCache: The disk snapshot of entity states.
    ///   - push: The app's push coordinator (the app delegate's, so system callbacks reach it).
    ///   - location: The app's location coordinator (the app delegate's, created at launch for zone relaunches).
    ///   - liveActivities: The app's Live Activity coordinator (the app delegate's, so its buttons work at launch).
    ///   - spotlight: Where the app's pages are indexed; inert unless the app passes ``CoreSpotlightIndexer``.
    public init(tokenStore: TokenStore = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup),
                snapshotCache: EntitySnapshotCache = .init(), push: PushCoordinator = .inert(),
                location: LocationCoordinator? = nil, liveActivities: LiveActivityCoordinator? = nil,
                spotlight: any SpotlightIndexing = InertSpotlightIndexer()) {
        self.spotlight = spotlight
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
        }
        // FENTON_HASS_TOKEN signs in with a long-lived access token for this launch only (never saved),
        // so journeys can run against the real server without a password.
        if let token = ProcessInfo.processInfo.environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let server = ProcessInfo.processInfo.environment["FENTON_HASS_SERVER"]
                .flatMap(URL.init(string:)).map(HassServer.init(baseURL:)) ?? .fentonHome
            let tokens = AuthTokens(accessToken: token, expiresAt: .distantFuture, refreshToken: "")
            start(server: server, tokens: TokenManager(store: InMemoryTokenStore(), initial: tokens))
            return
        }
        #endif
        if let stored = tokenStore.load() {
            start(server: stored.server, tokens: TokenManager(store: tokenStore))
        }
    }

    /// Completes sign-in with fresh tokens.
    public func didSignIn(server: HassServer, tokens: AuthTokens) throws {
        try tokenStore.save(StoredCredentials(server: server, refreshToken: tokens.refreshToken))
        start(server: server, tokens: TokenManager(store: tokenStore, initial: tokens))
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
        spotlight.removeAll()
        phase = .signedOut
        let push = push, liveActivities = liveActivities
        Task {
            // Nothing of the signed-in person stays on a Lock Screen.
            await liveActivities?.sessionEnded()
            await push.sessionEnded()
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
        liveActivities?.sessionStarted(store: connection.store)
        // Created before the phase changes so the first signed-in frame already has the cached photo.
        backdrop = HouseBackdropStore.session(for: server)
        phase = .signedIn(connection, lifecycle)
        spotlight.indexPages(SpotlightCatalog.entries)
        lifecycle.didBecomeActive()
    }
}
