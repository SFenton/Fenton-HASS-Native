import HassCore
import HassDesign
import SwiftUI

/// The Settings tab's root page (owner, 2026-10-16: Settings is its own page like the web's, the last tab).
///
/// A household topic is a value on the tab's own path (``ShellNavigator/paths``), not a `navigationDestination(item:)`,
/// so the shell sees when the tab is deeper than its root (the flyout's leading-edge swipe leaves the edge to the
/// system back swipe there). Outside the shell the list just does nothing on a tap.
struct SettingsTabRoot: View {
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?

    var body: some View {
        SettingsScreen(openTopic: Binding(
            get: { nil },
            set: { topic in
                guard let topic else { return }
                navigator?.paths[.settings, default: NavigationPath()].append(topic)
            }
        ))
    }
}

/// The page a ``SettingsRoute`` opens.
struct SettingsRouteDestination: View {
    var route: SettingsRoute

    var body: some View {
        switch route {
        case .vacation: VacationRoute()
        case .adminTodo: AdminTodoScreen()
        case .performance: PerformanceScreen()
        }
    }
}
