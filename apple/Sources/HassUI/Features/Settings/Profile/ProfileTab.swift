import HassCore
import HassDesign
import SwiftUI

/// The Summary sheet's Profile tab: the app's own extras that used to be the long Account list. Who is signed in and to
/// which server, who is home, Location on phones, and Sign Out behind the sheet's alert.
///
/// HIG: [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) (sections group
/// related rows) and [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) (Location's switch).
struct ProfileTab: View {
    @Binding var confirmsSignOut: Bool
    @Binding var showsLocationPermission: Bool
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(EntityStore.self) private var store: EntityStore?
    /// Nil on iPad and in launches that don't report location, which hides the Location section.
    @Environment(LocationCoordinator.self) private var location: LocationCoordinator?

    var body: some View {
        List {
            Section {
                AccountHeader(name: navigator?.profileName, server: serverLine)
                    .listRowBackground(Color.clear)
            }
            if let store {
                ProfilePeopleSection(store: store)
            }
            if let location {
                LocationAccountSection(location: location, showsPermission: $showsLocationPermission)
            }
            Section {
                Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                    .foregroundStyle(HassTokens.Ink.danger)
                    .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                    .accessibilityIdentifier("account.signOut")
            }
        }
        .accessibilityIdentifier("account.list")
    }

    /// The line under the name: the server they are signed in to, hidden in shared screenshots.
    private var serverLine: String {
        connection.map { HomeAssistantSettingsView.displayedServer($0.server, redacting: ScreenshotPrivacy.isRedacting) }
            ?? "Home Assistant"
    }
}
