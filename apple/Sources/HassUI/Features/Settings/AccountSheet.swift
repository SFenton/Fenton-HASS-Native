import HassCore
import HassDesign
import SwiftUI

/// The Account sheet behind the profile avatar (`.agents/design/direction-g.md`, Navigation): who is signed in,
/// Settings with every sub-page pushed inside the sheet, and Sign Out behind an alert.
///
/// Direction G puts People at Home and Your Summary here too; the app has not ported them yet (the web's Daily
/// Report), so the sheet shows what exists. HIG: [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
/// (a close button, not Done, for a viewing sheet) and [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
/// (confirm a destructive action that is hard to undo; the destructive button is red).
struct AccountSheet: View {
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(\.dismiss) private var dismiss
    @State private var openTopic: HouseholdSettingsPage?
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AccountHeader(name: navigator?.profileName, server: serverLine)
                        .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink {
                        AccountSettingsPage(openTopic: $openTopic)
                    } label: {
                        Label {
                            Text("Settings").foregroundStyle(HassTokens.Ink.primary)
                        } icon: {
                            Image(systemName: "gearshape").foregroundStyle(HassTokens.Ink.secondary)
                        }
                        .frame(minHeight: HassTokens.minTarget)
                    }
                    .accessibilityIdentifier("account.settings")
                }
                Section {
                    Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                        .foregroundStyle(HassTokens.Ink.danger)
                        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                        .accessibilityIdentifier("account.signOut")
                }
            }
            .modalChrome()
            .navigationTitle("Account")
            .inlineNavigationTitle()
            // The header names the person; without a name it already says "Signed In".
            .sheetSubtitle(navigator?.profileName == nil ? nil : "Signed In")
            .toolbar { SheetCloseItem(identifier: "account.close") { dismiss() } }
            .alert("Sign Out of Home Assistant?", isPresented: $confirmsSignOut) {
                Button("Sign Out", role: .destructive) { signOut() }
                    .accessibilityIdentifier("account.signOut.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need your username and password to sign in again.")
            }
        }
        // Pages pushed inside the sheet take the sheet's chrome, not the wallpaper (``SwiftUI/View/pageChrome()``).
        .environment(\.tileSurface, .sheet)
        .accessibilityIdentifier("account.sheet")
    }

    /// The line under the name: the server they are signed in to, hidden in shared screenshots.
    private var serverLine: String {
        connection.map { HomeAssistantSettingsView.displayedServer($0.server, redacting: ScreenshotPrivacy.isRedacting) }
            ?? "Home Assistant"
    }

    private func signOut() {
        dismiss()
        session?.signOut()
    }
}

/// The signed-in person at the top of the Account sheet, centred as in Apple's account sheets (direction G mockup
/// n1 profile): a large monogram, their name and the server they are signed in to.
private struct AccountHeader: View {
    var name: String?
    var server: String
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 84

    var body: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            Text(ProfileButton.initials(name) ?? "")
                .font(.system(size: avatarSize * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(HassTokens.Ink.actionFill, in: Circle())
                .overlay { if ProfileButton.initials(name) == nil { Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.white) } }
                .accessibilityHidden(true)
            Text(name ?? "Signed In")
                .font(.title2.weight(.bold))
                .foregroundStyle(HassTokens.Ink.primary)
                .multilineTextAlignment(.center)
            Text(server)
                .font(.subheadline)
                .foregroundStyle(HassTokens.Ink.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HassTokens.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.header")
    }
}

/// Settings pushed inside the Account sheet, with each topic pushed after it. A sheet never splits.
private struct AccountSettingsPage: View {
    @Binding var openTopic: HouseholdSettingsPage?

    var body: some View {
        SettingsScreen(openTopic: $openTopic)
            .modalChrome()
            .navigationDestination(item: $openTopic) { page in
                HouseholdSettingsDestination(page: page).modalChrome()
            }
    }
}

extension View {
    /// Presents the Account sheet (direction G: the profile avatar opens it on every tab root).
    func accountSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { AccountSheet().hassSheet(.form) }
    }
}
