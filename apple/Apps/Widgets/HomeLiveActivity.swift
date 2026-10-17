import ActivityKit
import AppIntents
import FentonActivityModel
import FentonActivityViews
import SwiftUI
import WidgetKit

/// The Home Live Activity (`.agents/platforms/apple/live-activities.md` §4): Lock Screen and banner, StandBy, the
/// Dynamic Island (compact, minimal, expanded), and on iOS 18 the `.small` family for Apple Watch and CarPlay.
///
/// All of the drawing is in `FentonActivityViews`; this file only places it, adds the buttons (App Intents live in
/// `Apps/Shared`, so the package cannot name them), and sets the system chrome. The views have no network and no
/// Keychain.
struct HomeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return configuration.supplementalActivityFamilies([.small])
        }
        return configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: HomeActivityAttributes.self) { context in
            HomeActivityFamilyView(state: context.state, tag: context.attributes.tag, isStale: context.isStale)
                .environment(\.activityActions, .intents)
                .activityBackgroundTint(ActivityStyle.ground)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(ActivityDeepLink.url(for: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { HomeActivityIsland.ExpandedLeading(state: context.state) }
                DynamicIslandExpandedRegion(.trailing) { HomeActivityIsland.ExpandedTrailing(state: context.state) }
                DynamicIslandExpandedRegion(.center) { HomeActivityIsland.ExpandedCenter(state: context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    HomeActivityIsland.ExpandedBottom(state: context.state, tag: context.attributes.tag)
                        .environment(\.activityActions, .intents)
                }
            } compactLeading: {
                HomeActivityIsland.CompactLeading(state: context.state)
            } compactTrailing: {
                HomeActivityIsland.CompactTrailing(state: context.state)
            } minimal: {
                HomeActivityIsland.Minimal(state: context.state)
            }
            .widgetURL(ActivityDeepLink.url(for: context.state))
            .keylineTint(ActivityStyle(tint: context.state.focusedJob?.tint ?? "neutral").accent)
        }
    }
}

/// Picks the presentation for the activity's family: the full Lock Screen view, or the small one for the Smart Stack
/// and CarPlay (iOS 18), where buttons do nothing until a device check says otherwise.
private struct HomeActivityFamilyView: View {
    let state: HomeActivityState
    let tag: String
    let isStale: Bool
    @Environment(\.isActivityFullscreen) private var isFullscreen

    var body: some View {
        let shown = isStale ? state.markingUpdating() : state
        if #available(iOS 18.0, *) {
            FamilyAwareView(state: shown, tag: tag, isFullscreen: isFullscreen)
        } else {
            HomeActivityLockScreenView(state: shown, tag: tag, isFullscreen: isFullscreen)
        }
    }
}

@available(iOS 18.0, *)
private struct FamilyAwareView: View {
    let state: HomeActivityState
    let tag: String
    let isFullscreen: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            HomeActivitySmallView(state: state)
        default:
            HomeActivityLockScreenView(state: state, tag: tag, isFullscreen: isFullscreen)
        }
    }
}

extension ActivityActions {
    /// Buttons that run the App Intents in `Apps/Shared/LiveActivityIntents.swift`.
    static let intents = ActivityActions(
        control: { tag, job, control, label in
            AnyView(Button(intent: JobControlIntent(tag: tag, job: job.id, control: control.id)) { label }.buttonStyle(.plain))
        },
        focus: { tag, job, label in
            AnyView(Button(intent: FocusJobIntent(tag: tag, job: job)) { label }.buttonStyle(.plain))
        })
}
