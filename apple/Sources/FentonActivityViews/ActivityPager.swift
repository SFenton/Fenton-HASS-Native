import FentonActivityModel
import SwiftUI

/// ‹ 2 of 3 ›: pages the focused job. Each arrow is a 44 pt button that reads "Previous job" or "Next job" and says
/// where the pager stands; the middle label is hidden from VoiceOver because the buttons carry it.
struct ActivityPager: View {
    let pager: HomeActivityState.Pager?
    let tag: String
    @Environment(\.activityActions) private var actions

    var body: some View {
        if let pager {
            HStack(spacing: 0) {
                actions.focus(tag, pager.previous, AnyView(arrow("chevron.left")))
                    .accessibilityLabel("Previous job")
                    .accessibilityValue(pager.label)
                Text(pager.label)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .accessibilityHidden(true)
                actions.focus(tag, pager.next, AnyView(arrow("chevron.right")))
                    .accessibilityLabel("Next job")
                    .accessibilityValue(pager.label)
            }
        }
    }

    private func arrow(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ActivityStyle.primaryText)
            .frame(minWidth: ActivityStyle.minimumHit, minHeight: ActivityStyle.minimumHit)
            .contentShape(Rectangle())
    }
}
