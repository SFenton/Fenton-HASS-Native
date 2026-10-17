import FentonActivityModel
import SwiftUI

/// The trailing side of a job: a live countdown, an estimate, a percentage or a state word.
///
/// `Text(timerInterval:)` counts on its own with no pushes, which is how a Live Activity shows a ticking time. It
/// takes all the width it is offered, so every use is framed.
struct ActivityTrailing: View {
    let job: ActivityJob
    /// Draws the figure in the accent colour of the job (the island's expanded trailing region).
    var emphasized = false
    /// Largest width the figure may take.
    var width: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        content
            .font(emphasized ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(ActivityStyle.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var content: some View {
        switch job.trailing {
        case let .countdown(range):
            Text(timerInterval: range, pauseTime: nil, countsDown: true, showsHours: (range.upperBound.timeIntervalSince(range.lowerBound)) >= 3600)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : width, alignment: .trailing)
        case let .approximately(date):
            VStack(alignment: .trailing, spacing: 0) {
                Text("About").font(.caption2).foregroundStyle(ActivityStyle.secondaryText)
                Text(date, style: .time)
            }
        case let .startsAt(date):
            VStack(alignment: .trailing, spacing: 0) {
                Text("Starts").font(.caption2).foregroundStyle(ActivityStyle.secondaryText)
                Text(date, style: .time)
            }
        case let .percent(value):
            Text("\(value)%")
        case .paused:
            Label("Paused", systemImage: "pause.fill").labelStyle(.titleAndIcon)
        case .attention:
            Label("Check", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(ActivityStyle.destructive)
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
        case .none:
            EmptyView()
        }
    }
}
