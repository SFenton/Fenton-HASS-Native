import FentonActivityModel
import SwiftUI

/// The apple-watch Smart Stack and CarPlay presentation (`.small` supplemental family, iOS 18): the focused job's
/// glyph, its countdown and "+N". No controls: buttons do nothing there until a device check says otherwise.
public struct HomeActivitySmallView: View {
    private let state: HomeActivityState

    /// Creates the view.
    public init(state: HomeActivityState) { self.state = state }

    public var body: some View {
        if let job = state.focusedJob {
            HStack(spacing: 6) {
                ActivityGlyph(job: job, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(job.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ActivityStyle.primaryText)
                        .lineLimit(1)
                    ActivityTrailing(job: job, width: 56)
                }
                if state.jobs.count > 1 {
                    Text("+\(state.jobs.count - 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ActivityStyle.secondaryText)
                        .accessibilityLabel("\(state.jobs.count - 1) more")
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
