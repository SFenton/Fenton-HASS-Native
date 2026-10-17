import FentonActivityModel
import SwiftUI

/// The focused job's line: the pager on the left, its controls on the right. Nothing for a job without either.
struct ActivityFocusLine: View {
    let state: HomeActivityState
    let tag: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let job = state.focusedJob, state.pager != nil || !job.controls.isEmpty || job.phase == .stopping {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    ActivityControls(job: job, tag: tag)
                    ActivityPager(pager: state.pager, tag: tag)
                }
            } else {
                HStack(spacing: 8) {
                    ActivityPager(pager: state.pager, tag: tag)
                    Spacer(minLength: 0)
                    ActivityControls(job: job, tag: tag)
                }
            }
        }
    }
}
