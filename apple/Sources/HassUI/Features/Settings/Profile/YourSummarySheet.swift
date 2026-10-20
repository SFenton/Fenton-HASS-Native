import HassCore
import HassDesign
import SwiftUI

/// "Your Summary", the sheet behind the header Profile button (owner, 2026-10-17): the web's Daily Report modal
/// (`ha-sfenton-react-dash@f5a7bf9:src/components/hass/DailyReportModal.tsx`) with four bottom tabs: Profile (the app's own
/// extras), Overdue Chores, Upcoming Chores and Expired Food. Spec: `.agents/pages/settings/profile.md`.
///
/// It opens on Overdue Chores, so the summary comes first and the account is one tab away. The title reads "Your Summary"
/// for a household resident and "Summary" for anyone else (``ProfileSummary/title(viewer:)``), who sees Profile and Expired
/// Food only (``SummaryTab/tabs(viewer:)``). The tabs use the shared modal bar (``SwiftUI/View/modalTabBar(_:label:title:symbol:badge:selection:identifier:placement:)``):
/// icons on compact width, icon over title on iPad and the unfolded Duo, a menu at accessibility text sizes.
///
/// HIG: [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) (a close button, not Done, for a
/// viewing sheet), [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)
/// (closely related views of one summary) and [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
/// (confirm a destructive action that is hard to undo; the destructive button is red).
struct YourSummarySheet: View {
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(EntityStore.self) private var store: EntityStore?
    /// Nil on iPad and in launches that don't report location, which hides the Location section.
    @Environment(LocationCoordinator.self) private var location: LocationCoordinator?
    @Environment(ChoresModel.self) private var chores: ChoresModel?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ChoresModel.viewerDefaultsKey) private var viewerUserId: String?
    /// The tab the reader picked, or the one the sheet was asked to open on; nil until then (the viewer decides the default).
    @State private var requested: SummaryTab?
    @State private var confirmsSignOut = false
    @State private var showsLocationPermission = false

    /// - Parameter opening: The tab to open on, when it is not the viewer's default (tests and the gallery).
    init(opening: SummaryTab? = nil) {
        _requested = State(initialValue: opening)
    }

    /// The household resident viewing: a shared chores model's when the environment has one (the gallery's, which is
    /// authoritative even for a guest), else the remembered Home Assistant user.
    private var viewer: ChoresConfig.Resident? {
        guard let chores else { return ChoresConfig.Resident.forUserId(viewerUserId) }
        return chores.viewer
    }

    private var tabs: [SummaryTab] { SummaryTab.tabs(viewer: viewer) }

    private var selected: SummaryTab {
        requested.flatMap { tabs.contains($0) ? $0 : nil } ?? SummaryTab.initial(viewer: viewer)
    }

    var body: some View {
        let counts = store.map { ProfileSummary.counts(viewer: viewer, store: $0) } ?? SummaryCounts(overdue: 0, expiredFood: 0)
        NavigationStack {
            SummaryPanel(tab: selected, viewer: viewer, confirmsSignOut: $confirmsSignOut, showsLocationPermission: $showsLocationPermission)
                .modalChrome()
                .modalTabBar(tabs, label: SummaryTab.barLabel, title: \.title,
                             symbol: { SymbolMap.symbol(for: $0.mdiIcon) }, badge: { counts.badge(for: $0) },
                             selection: Binding(get: { selected }, set: { requested = $0 }), identifier: "summary.tabs")
                .navigationTitle(ProfileSummary.title(viewer: viewer))
                .inlineNavigationTitle()
                .toolbar { SheetCloseItem(identifier: "account.close") { dismiss() } }
                .sheet(isPresented: $showsLocationPermission) {
                    if let location {
                        LocationPermissionSheet(location: location) { showsLocationPermission = false }
                    }
                }
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
