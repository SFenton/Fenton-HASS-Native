#if DEBUG
import FentonActivityModel
import FentonActivityViews
import HassDesign
import SwiftUI

/// Gallery page for the Home Live Activity (`.agents/platforms/apple/live-activities.md` §4, §11): the Lock Screen
/// view and the Dynamic Island presentations drawn by the same views the widget extension uses, over fixture content,
/// with buttons that behave like the real ones (‹ › page, a control shows "Stopping…") and record their press.
///
/// `FENTON_GALLERY_SCENARIO` picks the content (`HomeActivityFixtures.Scenario`, default `three`). Launch with
/// `FENTON_GALLERY=live-activity`.
struct LiveActivityGallery: View {
    @State private var state: HomeActivityState
    @State private var lastAction = "none"

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let scenario = environment["FENTON_GALLERY_SCENARIO"].flatMap(HomeActivityFixtures.Scenario.init(rawValue:)) ?? .three
        _state = State(initialValue: HomeActivityFixtures.state(scenario))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                if !GalleryEnvironment.isClean {
                    GalleryLastCall(text: lastAction, title: "Last action")
                }
                section("Lock Screen") {
                    // The Lock Screen's width on a phone; a tablet shows 425 or 500 pt.
                    HomeActivityLockScreenView(state: state)
                        .frame(maxWidth: 420)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ActivityStyle.ground))
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("liveactivity.lockscreen")
                }
                section("Dynamic Island, compact") { HomeActivityIslandPreview(state: state, kind: .compact) }
                section("Dynamic Island, minimal") { HomeActivityIslandPreview(state: state, kind: .minimal) }
                section("Dynamic Island, expanded") { HomeActivityIslandPreview(state: state, kind: .expanded) }
                section("Small (Smart Stack, CarPlay)") {
                    HomeActivitySmallView(state: state)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("liveactivity.small")
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .environment(\.activityActions, actions)
        .navigationTitle("Live Activity")
    }

    /// Buttons like the intents: ‹ › focus a job, a control shows the job as stopping.
    private var actions: ActivityActions {
        ActivityActions(
            control: { _, job, control, label in
                AnyView(Button(action: { press(control, on: job) }) { label }.buttonStyle(.plain))
            },
            focus: { _, job, label in
                AnyView(Button(action: { focus(job) }) { label }.buttonStyle(.plain))
            })
    }

    private func press(_ control: ActivityControl, on job: ActivityJob) {
        lastAction = "\(control.id) \(job.id)"
        state = state.stopping(job.id)
    }

    private func focus(_ job: String) {
        lastAction = "focus \(job)"
        state = state.focusing(job)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
#endif
