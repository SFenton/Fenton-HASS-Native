import FentonActivityModel
import SwiftUI

/// The Lock Screen, banner and StandBy presentation of the Home activity (`live-activities.md` §4).
///
/// Header ("Home · 3 running"), job rows, and one line for the focused job: the pager (‹ 2 of 3 ›) and its one or two
/// controls. The Lock Screen limit is 160 pt, so two rows fit with the controls line (measured by
/// `ActivityLayoutTests`), and a larger text size shows only the focused job.
public struct HomeActivityLockScreenView: View {
    private let state: HomeActivityState
    private let tag: String
    private let isFullscreen: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Creates the view.
    /// - Parameters:
    ///   - state: The activity's content.
    ///   - tag: The activity's tag, which the buttons carry.
    ///   - isFullscreen: StandBy: the header goes and everything scales up (the system scales the view; the view only
    ///     drops what the larger presentation does not need).
    public init(state: HomeActivityState, tag: String = HomeActivityAttributes.homeTag, isFullscreen: Bool = false) {
        self.state = state
        self.tag = tag
        self.isFullscreen = isFullscreen
    }

    /// Rows that fit above the controls line at the current text size.
    private var rowLimit: Int {
        if typeSize.isAccessibilitySize { return 1 }
        return state.focusedJob.map { !$0.controls.isEmpty } == true || state.pager != nil ? 2 : HomeActivityState.maxLockScreenRows
    }

    public var body: some View {
        let rows = state.lockScreenRows(limit: rowLimit)
        VStack(alignment: .leading, spacing: 5) {
            if !isFullscreen { header(overflow: state.overflowCount(limit: rowLimit)) }
            ForEach(rows) { job in
                ActivityJobRow(job: job, isFocused: rows.count > 1 && job.id == state.focusedJob?.id)
            }
            ActivityFocusLine(state: state, tag: tag)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func header(overflow: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill").accessibilityHidden(true)
            Text("Home")
            Text(state.runningCount == 0 ? "Done" : "\(state.runningCount) running")
                .foregroundStyle(ActivityStyle.secondaryText)
            Spacer(minLength: 0)
            if overflow > 0 {
                Text("+\(overflow) more").foregroundStyle(ActivityStyle.secondaryText)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ActivityStyle.primaryText)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The focused job's line: the pager on the left, its controls on the right. Nothing for a job without either.
struct ActivityFocusLine: View {
    let state: HomeActivityState
    let tag: String
    @Environment(\.activityActions) private var actions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let job = state.focusedJob {
            let pager = state.pager
            if pager != nil || !job.controls.isEmpty || job.phase == .stopping {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { controls(for: job); pagerView(pager) }
                } else {
                    HStack(spacing: 8) {
                        pagerView(pager)
                        Spacer(minLength: 0)
                        controls(for: job)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pagerView(_ pager: HomeActivityState.Pager?) -> some View {
        if let pager {
            HStack(spacing: 0) {
                actions.focus(tag, pager.previous, AnyView(pagerLabel(systemName: "chevron.left")))
                    .accessibilityLabel("Previous job")
                    .accessibilityValue(pager.label)
                Text(pager.label)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .accessibilityHidden(true)
                actions.focus(tag, pager.next, AnyView(pagerLabel(systemName: "chevron.right")))
                    .accessibilityLabel("Next job")
                    .accessibilityValue(pager.label)
            }
        }
    }

    private func pagerLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ActivityStyle.primaryText)
            .frame(minWidth: ActivityStyle.minimumHit, minHeight: ActivityStyle.minimumHit)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func controls(for job: ActivityJob) -> some View {
        if job.phase == .stopping {
            Text("Stopping…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ActivityStyle.secondaryText)
                .frame(minHeight: ActivityStyle.minimumHit)
        } else {
            HStack(spacing: 8) {
                ForEach(job.controls) { control in
                    actions.control(tag, job, control, AnyView(controlLabel(control)))
                        .accessibilityLabel("\(control.title) \(job.title)")
                }
            }
        }
    }

    private func controlLabel(_ control: ActivityControl) -> some View {
        Text(control.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(control.role == .destructive ? ActivityStyle.destructive : ActivityStyle.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: ActivityStyle.minimumHit)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .contentShape(Capsule())
    }
}
