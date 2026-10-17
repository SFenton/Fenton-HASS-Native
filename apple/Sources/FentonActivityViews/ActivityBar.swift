import FentonActivityModel
import SwiftUI

/// The thin bar under a row: fills itself from the timer range, or draws a reported fraction.
struct ActivityBar: View {
    let job: ActivityJob
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        // Always-On: the bars are the first thing to go (`live-activities.md` §4).
        if !isLuminanceReduced {
            bar
                .tint(ActivityStyle(tint: job.tint).accent)
                .frame(height: 3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var bar: some View {
        switch job.bar {
        case let .timer(range):
            ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
        case let .fraction(value):
            ProgressView(value: value)
        case .full:
            ProgressView(value: 1)
        case .hidden:
            Color.clear
        }
    }
}
