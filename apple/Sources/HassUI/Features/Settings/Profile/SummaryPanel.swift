import HassCore
import HassDesign
import SwiftUI

/// The selected tab's content, cross-faded when the tab changes (HIG Motion: Reduce Motion fades only).
///
/// The chore tabs need the shared ``ChoresModel`` (the Donetick edit form reads it), which only the Chores tab provides, so
/// the panel hosts one when the environment has none.
struct SummaryPanel: View {
    var tab: SummaryTab
    var viewer: ChoresConfig.Resident?
    @Binding var confirmsSignOut: Bool
    @Binding var showsLocationPermission: Bool
    @Environment(ChoresModel.self) private var injected: ChoresModel?
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(HassConnection.self) private var connection: HassConnection?
    @Environment(EntityStore.self) private var store: EntityStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hosted: ChoresModel?

    var body: some View {
        let chores = injected ?? hosted
        ZStack {
            content(chores)
                .id(tab)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: tab)
        .onAppear {
            if injected == nil, hosted == nil, let connection { hosted = .live(connection: connection, session: session) }
        }
        .task(id: hosted != nil) { await hosted?.refreshViewer() }
    }

    @ViewBuilder
    private func content(_ chores: ChoresModel?) -> some View {
        switch tab {
        case .profile:
            ProfileTab(confirmsSignOut: $confirmsSignOut, showsLocationPermission: $showsLocationPermission)
        case .overdue, .upcoming:
            if let store, let chores, let viewer {
                SummaryChoresTab(tab: tab, lists: ProfileSummary.lists(for: viewer), viewer: viewer, store: store)
                    .environment(chores)
            } else {
                Color.clear
            }
        case .expiredFood:
            if let store {
                SummaryExpiredFoodTab(store: store)
            } else {
                Color.clear
            }
        }
    }
}
