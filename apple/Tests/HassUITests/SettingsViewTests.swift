import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
@testable import HassUI
import SwiftUI
import Testing

@MainActor
struct SettingsViewTests {
    private let admin = HassUser(id: "1", name: "Stephen", isOwner: false, isAdmin: true)
    private let member = HassUser(id: "2", name: "Guest", isOwner: false, isAdmin: false)

    @Test func rowCopyMatchesTheWeb() {
        #expect(HomeAssistantSettingsView.linkTitle == "Home Assistant Settings")
        #expect(HomeAssistantSettingsView.linkSubtitle == "Access more in-depth Home Assistant details and settings.")
    }

    @Test func serverShowsHostAndPort() {
        let plain = HassServer(baseURL: URL(string: "https://ha.example.com")!)
        let ported = HassServer(baseURL: URL(string: "http://192.168.1.2:8123")!)
        #expect(HomeAssistantSettingsView.displayedServer(plain, redacting: false) == "ha.example.com")
        #expect(HomeAssistantSettingsView.displayedServer(ported, redacting: false) == "192.168.1.2:8123")
        #expect(HomeAssistantSettingsView.displayedServer(plain, redacting: true) == "Hidden for screenshot")
    }

    @Test func userNameAndRole() {
        #expect(HomeAssistantSettingsView.displayedName(admin, redacting: false) == "Stephen")
        #expect(HomeAssistantSettingsView.displayedName(HassUser(id: "3", name: "", isOwner: false, isAdmin: false), redacting: false) == "Unnamed user")
        #expect(HomeAssistantSettingsView.displayedName(admin, redacting: true) == "Hidden for screenshot")
        #expect(admin.roleTitle == "Administrator")
        #expect(member.roleTitle == "User")
        #expect(HassUser(id: "4", name: nil, isOwner: true, isAdmin: true).roleTitle == "Owner")
    }

    @Test func statusAndVersion() {
        #expect(HomeAssistantSettingsView.statusText(.connected(version: "2026.10.1")) == "Connected")
        #expect(HomeAssistantSettingsView.statusText(.waitingToReconnect) == "Reconnecting…")
        #expect(HomeAssistantSettingsView.statusText(.rejected) == "Signed out by server")
        #expect(HomeAssistantSettingsView.version(.connected(version: "2026.10.1")) == "2026.10.1")
        #expect(HomeAssistantSettingsView.version(.connecting) == nil)
    }

    @Test func settingsPageNeedsAnAdministrator() {
        #expect(HomeAssistantSettingsView.webPages(for: nil) == [.settings, .profile])
        #expect(HomeAssistantSettingsView.webPages(for: admin) == [.settings, .profile])
        #expect(HomeAssistantSettingsView.webPages(for: member) == [.profile])
        #expect(HomeAssistantSettingsView.WebPage.settings.path == "/config")
        #expect(HomeAssistantSettingsView.WebPage.profile.path == "/profile")
    }

    /// Hosted render of the Settings tab and the modal without a live connection.
    @Test func settingsRenderOffline() {
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID()).json")))
        let store = EntityStore()
        let connection = HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        for view in [AnyView(NavigationStack { SettingsScreen() }), AnyView(HomeAssistantSettingsView())] {
            let hosted = view
                .environment(session)
                .environment(connection)
                .environment(store)
                .frame(width: 402, height: 874)
            #expect(ImageRenderer(content: hosted).cgImage != nil)
        }
    }

    /// Renders a view with the app's environment.
    private func render(_ view: some View, connection: HassConnection? = nil) -> CGImage? {
        let session = AppSession(tokenStore: InMemoryTokenStore(), snapshotCache: EntitySnapshotCache(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID()).json")))
        let store = EntityStore()
        let connection = connection
            ?? HassConnection(server: .fentonHome, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        let hosted = view
            .environment(session)
            .environment(connection)
            .environment(store)
            .frame(width: 402, height: 874)
        return ImageRenderer(content: hosted).cgImage
    }

    private func mockConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID()).json"))
        return (HassConnection(server: .fentonHome, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    /// Waits for the observer that maps HAKit's state onto `status`.
    private func waitForStatus(_ connection: HassConnection, _ isExpected: (HassConnection.Status) -> Bool) async {
        for _ in 0..<1_000 where !isExpected(connection.status) { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func linkRowRendersWithAndWithoutChevron() {
        for chevron in [true, false] {
            let row = SettingsLinkRow(title: "Settings", subtitle: "Devices.", symbol: "gearshape", showsChevron: chevron)
            #expect(render(row) != nil)
        }
    }

    @Test func modalRendersTheAccount() {
        #expect(render(HomeAssistantSettingsView(user: admin)) != nil)
        #expect(render(HomeAssistantSettingsView(user: member)) != nil)
    }

    @Test func accountWaitsWhileConnectingAndFailsOffline() async {
        let (connection, mock) = mockConnection()
        #expect(await HomeAssistantSettingsView.loadedUser(nil, from: connection) == (nil, true))
        #expect(await HomeAssistantSettingsView.loadedUser(admin, from: connection) == (admin, false))
        mock.setState(.connecting, waitForQueue: false)
        await waitForStatus(connection) { $0 == .connecting }
        #expect(await HomeAssistantSettingsView.loadedUser(nil, from: connection) == (nil, false))
    }

    @Test func accountLoadsWhileConnected() async throws {
        let (connection, mock) = mockConnection()
        mock.setState(.ready(version: "2026.10.1"), waitForQueue: false)
        await waitForStatus(connection) { $0 == .connected(version: "2026.10.1") }

        async let loaded = HomeAssistantSettingsView.loadedUser(nil, from: connection)
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        try #require(mock.pendingRequests.first).completion(.success(HAData(value: ["id": "1", "name": "Stephen", "is_admin": true])))
        #expect(await loaded == (admin, false))

        async let failed = HomeAssistantSettingsView.loadedUser(nil, from: connection)
        for _ in 0..<1_000 where mock.pendingRequests.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        try #require(mock.pendingRequests.last).completion(.failure(.internal(debugDescription: "offline")))
        #expect(await failed == (nil, true))

        // Last: rendering runs the modal's own load, which leaves a request pending on the mock.
        #expect(render(HomeAssistantSettingsView(user: admin), connection: connection) != nil)
    }

    @Test func webPageNeedsFreshTokens() async {
        let server = HassServer.fentonHome
        #expect(await HomeAssistantWebPage.frontendSession(server: server, tokens: nil) == nil)
        #expect(await HomeAssistantWebPage.frontendSession(server: server, tokens: TokenManager(store: InMemoryTokenStore())) == nil)
        let tokens = AuthTokens(accessToken: "A", expiresAt: Date().addingTimeInterval(600), refreshToken: "R")
        let session = await HomeAssistantWebPage.frontendSession(server: server, tokens: TokenManager(store: InMemoryTokenStore(), initial: tokens))
        #expect(session == FrontendSession(server: server, tokens: tokens))
    }

    @Test func webPageRendersEachState() {
        let frontend = FrontendSession(
            server: .fentonHome,
            tokens: AuthTokens(accessToken: "A", expiresAt: Date().addingTimeInterval(600), refreshToken: "R"))
        for page in HomeAssistantSettingsView.WebPage.allCases {
            #expect(render(NavigationStack { HomeAssistantWebPage(page: page) }) != nil)
            #expect(render(NavigationStack { HomeAssistantWebPage(page: page, failed: true) }) != nil)
            #expect(render(NavigationStack { HomeAssistantWebPage(page: page, frontend: frontend) }) != nil)
            #expect(!page.title.isEmpty && !page.subtitle.isEmpty && !page.symbol.isEmpty && page.id == page.rawValue)
        }
    }
}
