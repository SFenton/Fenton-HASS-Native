#if os(macOS)
import AppKit
import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing

/// Sign-in state for the whole app, and the root view that follows it.
@MainActor
@Suite(.serialized)
struct AppSessionTests {
    /// A server nothing listens on: the connection a session starts fails at once and keeps to itself.
    static let server = HassServer(baseURL: URL(string: "http://127.0.0.1:1")!)
    static let tokens = AuthTokens(accessToken: "access", expiresAt: .distantFuture, refreshToken: "refresh")

    func cache() -> EntitySnapshotCache {
        EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "session-\(UUID()).json"))
    }

    func session(store: InMemoryTokenStore = InMemoryTokenStore()) -> (AppSession, InMemoryTokenStore) {
        (AppSession(tokenStore: store, snapshotCache: cache()), store)
    }

    func connection(of session: AppSession) -> HassConnection? {
        if case let .signedIn(connection, _) = session.phase { return connection }
        return nil
    }

    // MARK: Session

    @Test func aSessionWithNothingSavedStartsSignedOut() {
        let (session, _) = session()
        guard case .signedOut = session.phase else { Issue.record("expected signed out"); return }
        #expect(session.tokens == nil && session.backdrop == nil)
    }

    @Test func signingInSavesTheRefreshTokenAndOpensAConnection() throws {
        let (session, store) = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        let connection = try #require(connection(of: session))
        #expect(connection.server == Self.server)
        #expect(session.tokens != nil && session.backdrop != nil)
        let saved = try #require(store.load())
        #expect(saved.server == Self.server && saved.refreshToken == "refresh")
        session.signOut()
    }

    @Test func aSavedSignInResumesWithoutTheNetwork() throws {
        let store = InMemoryTokenStore()
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        let (session, _) = session(store: store)
        #expect(connection(of: session)?.server == Self.server)
        session.signOut()
    }

    @Test func signingOutForgetsEverythingAndStopsTheConnection() async throws {
        let (session, store) = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        let connection = try #require(connection(of: session))
        connection.store.apply([EntityState(entityId: "light.test", state: "on")])
        #expect(connection.store.value("light.test") != nil)
        session.signOut()
        guard case .signedOut = session.phase else { Issue.record("expected signed out"); return }
        #expect(store.load() == nil, "the refresh token is gone from the Keychain")
        #expect(session.tokens == nil && session.backdrop == nil)
        #expect(connection.store.value("light.test") == nil, "the entity store is emptied")
        session.signOut()
    }

    @Test func aUITestLaunchStartsSignedOutEvenWithASavedSignIn() async throws {
        let store = InMemoryTokenStore()
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        let session = await withLaunch(environment: ["FENTON_UITEST_RESET": "1"]) { AppSession(tokenStore: store, snapshotCache: cache()) }
        guard case .signedOut = session.phase else { Issue.record("expected signed out"); return }
        #expect(store.load() == nil, "the reset cleared the saved sign-in")
    }

    @Test func aDebugTokenSignsInForThisLaunchOnly() async throws {
        let store = InMemoryTokenStore()
        let session = await withLaunch(environment: ["FENTON_HASS_TOKEN": "long-lived", "FENTON_HASS_SERVER": "http://127.0.0.1:1"]) {
            AppSession(tokenStore: store, snapshotCache: cache())
        }
        #expect(connection(of: session)?.server == Self.server)
        #expect(store.load() == nil, "a long-lived token is never saved")
        session.signOut()
        let blank = await withLaunch(environment: ["FENTON_HASS_TOKEN": ""]) { AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: cache()) }
        guard case .signedOut = blank.phase else { Issue.record("an empty token is not a sign-in"); return }
    }

    // MARK: Root view

    @Test func theRootShowsSignInThenTheAppThenSignInAgain() async throws {
        let (session, _) = session()
        let hosted = HostedWindow(RootView(session: session), size: CGSize(width: 402, height: 874))
        defer { hosted.close(); session.signOut() }
        await hosted.settle(0.8)
        let signIn = try #require(hosted.snapshot())
        #expect(signIn.distinctColors > 3)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        await hosted.settle(1.5)
        let app = try #require(hosted.snapshot())
        #expect(app.differs(from: signIn), "signing in swaps the form for the app's tabs")
        session.signOut()
        await hosted.settle(1.0)
        let again = try #require(hosted.snapshot())
        #expect(again.differs(from: app), "signing out takes the tabs away again")
    }

    @Test func aGalleryLaunchShowsTheGalleryInsteadOfSignIn() async throws {
        let (session, _) = session()
        let plain = HostedWindow(RootView(session: session), size: CGSize(width: 402, height: 874))
        defer { plain.close() }
        await plain.settle(0.6)
        let signIn = try #require(plain.snapshot())
        let gallery = await withLaunch(environment: ["FENTON_GALLERY": "direction-g"]) {
            let hosted = HostedWindow(RootView(session: session), size: CGSize(width: 402, height: 874))
            await hosted.settle(0.8)
            return hosted
        }
        defer { gallery.close() }
        #expect(try #require(gallery.snapshot()).differs(from: signIn))
    }
}
#endif
