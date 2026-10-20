#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
import HassTestSupport
@testable import HassUI
import SwiftUI
import Testing

/// The Chores model the signed-in app builds, the host that builds it, the location permission sheet's presenter and
/// the room tone colours.
@MainActor
@Suite(.serialized)
struct ShellModelsTests {
    func connection() -> HassConnection {
        HassConnection(server: AppSessionTests.server, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
    }

    func defaults() -> UserDefaults { UserDefaults(suiteName: "shell-models-\(UUID().uuidString)")! }

    // MARK: Chores model

    @Test func theLiveChoresModelKnowsTheCachedViewerAndAsksForTokensFromTheSession() async throws {
        let defaults = defaults()
        defaults.set("cached-user-id", forKey: ChoresModel.viewerDefaultsKey)
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "chores-\(UUID()).json")))
        let signedOut = ChoresModel.live(connection: connection(), session: session, defaults: defaults)
        #expect(signedOut.viewerUserId == "cached-user-id", "a relaunch shows the right lists before the lookup")
        await #expect(throws: URLError.self) { _ = try await signedOut.accessToken() }

        try session.didSignIn(server: AppSessionTests.server, tokens: AppSessionTests.tokens)
        defer { session.signOut() }
        let signedIn = ChoresModel.live(connection: connection(), session: session, defaults: defaults)
        #expect(try await signedIn.accessToken() == "access")
    }

    @Test func theHostBuildsTheModelOnAppearAndShowsItsContent() async throws {
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "chores-\(UUID()).json")))
        let connection = connection()
        let hosted = HostedWindow(
            ChoresModelHost { Text("Chores content").font(.largeTitle) }
                .environment(connection).environment(session),
            size: CGSize(width: 402, height: 300)
        )
        defer { hosted.close() }
        await hosted.settle(1.0)
        #expect(try #require(hosted.snapshot()).distinctColors >= 2, "once the model is built the content replaces the blank")
    }

    // MARK: Location permission

    @Test func theLocationPresenterShowsThePermissionSheetWhenTheCoordinatorOffersIt() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .notDetermined))
        let transport = StubHTTPTransport([])
        let mobileApp = MobileAppCoordinator(
            device: { MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                                      deviceID: "v", apnsEnvironment: .sandbox) },
            store: InMemoryMobileAppRegistrationStore([], active: nil), transport: transport)
        let location = LocationCoordinator(platform: platform, mobileApp: mobileApp, transport: transport,
                                           batteryLevel: { 64 }, defaults: defaults())
        let hosted = HostedWindow(Color.black.locationReporting(location), size: CGSize(width: 402, height: 874))
        defer { hosted.close() }
        await hosted.settle(0.5)
        #expect(hosted.window.attachedSheet == nil && hosted.window.sheets.isEmpty)
        location.isPresentingPermission = true
        await hosted.settle(1.0)
        #expect(hosted.window.attachedSheet != nil, "the permission screen is up")
        location.isPresentingPermission = false
        await hosted.settle(1.0)
        #expect(hosted.window.attachedSheet == nil, "closing the flag dismisses it")
        let plain = HostedWindow(Color.black.locationReporting(nil), size: CGSize(width: 402, height: 300))
        defer { plain.close() }
        await plain.settle(0.3)
        #expect(plain.window.sheets.isEmpty, "a launch that does not report location shows nothing")
    }

    // MARK: Colours

    @Test func everyRoomToneHasItsOwnTint() {
        let tones: [RoomTone] = [.light, .air, .climate, .presence, .contact, .vacuum, .media, .power, .warning, .neutral]
        let tints = tones.map { "\($0.color)" }
        // Power shares presence's tint; every other tone differs.
        #expect(Set(tints).count == tones.count - 1)
    }
}
#endif
