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
        phase = .signedOut
        if let stored {
            Task.detached { await HassLoginFlow.revoke(server: stored.server, refreshToken: stored.refreshToken) }
        }
    }

    private func start(server: HassServer, tokens: TokenManager) {
        let connection = HassConnection(server: server, tokens: tokens, store: EntityStore(), snapshotCache: snapshotCache)
        let lifecycle = ConnectionLifecycle(connection: connection)
        phase = .signedIn(connection, lifecycle)
        lifecycle.didBecomeActive()
    }
}
