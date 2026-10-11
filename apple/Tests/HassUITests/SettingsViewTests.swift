import Foundation
import HassCore
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
}
