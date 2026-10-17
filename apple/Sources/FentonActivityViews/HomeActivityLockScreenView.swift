import FentonActivityModel
import SwiftUI

/// The Lock Screen, banner and StandBy presentation of the Home activity (`live-activities.md` §4).
///
/// Job rows and one line for the focused job: the pager (‹ 2 of 3 ›) and its one or two controls. A single job also
/// gets the header ("Home · 1 running"). The Lock Screen limit is 160 pt (measured by `LiveActivityJourneyTests`), so
/// several jobs show two compact rows with the pager line and no header (the pager already says "2 of 3"), and a
/// larger text size shows only the focused job.
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
        VStack(alignment: .leading, spacing: 4) {
            if !isFullscreen && rows.count == 1 { header }
            ForEach(rows) { job in
                ActivityJobRow(job: job, isFocused: rows.count > 1 && job.id == state.focusedJob?.id, isCompact: rows.count > 1)
            }
            ActivityFocusLine(state: state, tag: tag)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rows.count > 1 ? "Home, \(state.runningCount) running" : "Home")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill").accessibilityHidden(true)
            Text("Home")
            Text(state.runningCount == 0 ? "Done" : "\(state.runningCount) running")
                .foregroundStyle(ActivityStyle.secondaryText)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ActivityStyle.primaryText)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
