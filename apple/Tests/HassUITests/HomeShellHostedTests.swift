#if os(macOS)
import AppKit
import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing

/// Home on the unfolded Duo's hinge, and the signed-in shell in each navigation style.
@MainActor
@Suite(.serialized)
struct HomeShellHostedTests {
    static let landscape = CGSize(width: 1200, height: 800)

    func connection() throws -> HassConnection {
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "home-\(UUID()).json"))
        try cache.save([
            EntityState(entityId: "light.lights", state: "on"),
            EntityState(entityId: "weather.pirate_weather", state: "sunny", attributes: ["temperature": .number(70)]),
            EntityState(entityId: "input_boolean.guests_staying_in_guest_room", state: "on"),
        ], server: .fentonHome)
        return HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore(), snapshotCache: cache)
    }

    func home(connection: HassConnection, hinge: CGRect?, regular: Bool) -> HostedWindow {
        HostedWindow(
            NavigationStack { HomeScreen() }
                .environment(connection).environment(connection.store)
                .environment(ShellNavigator())
                .environment(\.horizontalSizeClass, regular ? .regular : .compact)
                .environment(\.windowHinge, hinge),
            size: Self.landscape
        )
    }

    @Test func aHingeSplitsHomeIntoTwoColumnsAndNoHingeKeepsOne() async throws {
        let connection = try connection()
        let hinge = CGRect(x: 590, y: 0, width: 20, height: 800)
        let split = home(connection: connection, hinge: hinge, regular: true)
        defer { split.close() }
        let single = home(connection: connection, hinge: nil, regular: true)
        defer { single.close() }
        await split.settle(1.0)
        await single.settle(1.0)
        let columns = try #require(split.snapshot())
        let column = try #require(single.snapshot())
        #expect(columns.distinctColors > 3 && column.distinctColors > 3)
        #expect(columns.differs(from: column), "the hinge puts chips and weather on one side, cameras and guests on the other")
    }

    @Test func aCompactShellShowsTheTabBarAndARegularOneTheFlyout() async throws {
        func shell(regular: Bool) async throws -> NSBitmapImageRep {
            let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
                fileURL: FileManager.default.temporaryDirectory.appending(path: "shell-\(UUID()).json")))
            try session.didSignIn(server: AppSessionTests.server, tokens: AppSessionTests.tokens)
            let hosted = HostedWindow(
                RootView(session: session).environment(\.horizontalSizeClass, regular ? .regular : .compact),
                size: regular ? Self.landscape : CGSize(width: 402, height: 874)
            )
            defer { hosted.close(); session.signOut() }
            await hosted.settle(1.5)
            return try #require(hosted.snapshot())
        }
        let compact = try await shell(regular: false)
        let regular = try await shell(regular: true)
        #expect(compact.distinctColors > 3 && regular.distinctColors > 3)
        #expect(compact.differs(from: regular))
    }
}
#endif
