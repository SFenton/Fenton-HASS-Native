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

    /// Token source for the signed-in server, used by the Home Assistant settings web view.
    @ObservationIgnored public private(set) var tokens: TokenManager?

    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache

    /// Creates the session, resuming a saved sign-in if one exists. Restoring is synchronous and
    /// network-free, so the first frame already shows the cached Home screen.
    public init(tokenStore: TokenStore = KeychainTokenStore(), snapshotCache: EntitySnapshotCache = .init()) {
        self.tokenStore = tokenStore
        self.snapshotCache = snapshotCache
        #if DEBUG
        // UI tests start signed out: FENTON_UITEST_RESET=1 clears the saved sign-in and snapshot.
        if ProcessInfo.processInfo.environment["FENTON_UITEST_RESET"] == "1" {
            tokenStore.clear()
            snapshotCache.clear()
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

    /// Signs out: revokes the refresh token, clears the Keychain, cache and store.
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
        phase = .signedOut
        if let stored {
            Task.detached { await HassLoginFlow.revoke(server: stored.server, refreshToken: stored.refreshToken) }
        }
    }

    private func start(server: HassServer, tokens: TokenManager) {
        let connection = HassConnection(server: server, tokens: tokens, store: EntityStore(), snapshotCache: snapshotCache)
        let lifecycle = ConnectionLifecycle(connection: connection)
        self.tokens = tokens
        phase = .signedIn(connection, lifecycle)
        lifecycle.didBecomeActive()
    }
}
