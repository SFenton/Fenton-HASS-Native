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
    @Environment(\.dismiss) private var dismiss
    @State private var openTopic: HouseholdSettingsPage?
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AccountHeader(name: navigator?.profileName)
                }
                Section {
                    NavigationLink {
                        AccountSettingsPage(openTopic: $openTopic)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .foregroundStyle(HassTokens.Ink.primary)
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

    private func signOut() {
        dismiss()
        session?.signOut()
    }
}

/// The signed-in person at the top of the Account sheet: the avatar and their name.
private struct AccountHeader: View {
    var name: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The avatar grows with its initials, so they never truncate at accessibility sizes (it was a fixed 56 pt).
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 56

    /// Side by side, or the name under the avatar at accessibility sizes so it keeps the sheet's width.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.s))
            : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.m))
    }

    var body: some View {
        layout {
            Text(ProfileButton.initials(name) ?? "")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: diameter, height: diameter)
                .background(HassTokens.Ink.actionFill, in: Circle())
                .overlay { if ProfileButton.initials(name) == nil { Image(systemName: "person.fill").foregroundStyle(.white) } }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? "Signed In")
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                Text("Home Assistant")
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
        }
        .padding(.vertical, HassTokens.Spacing.xs)
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
