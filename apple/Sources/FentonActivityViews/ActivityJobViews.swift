import FentonActivityModel
import SwiftUI

/// A job's glyph in a tinted circle.
struct ActivityGlyph: View {
    let job: ActivityJob
    var size: CGFloat = 26

    var body: some View {
        let style = ActivityStyle(tint: job.tint)
        Image(systemName: job.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(style.accent)
            .frame(width: size, height: size)
            .background(Circle().fill(style.rowFill()))
            .accessibilityHidden(true)
    }
}

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

/// One job on the Lock Screen: glyph, title, status, the trailing figure and a thin bar, as a tinted glass row.
///
/// The row is one accessibility element whose children combine, so the countdown text is read live.
struct ActivityJobRow: View {
    let job: ActivityJob
    var isFocused = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let style = ActivityStyle(tint: job.tint)
        VStack(spacing: 4) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) { ActivityGlyph(job: job); title }
                    ActivityTrailing(job: job)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ActivityGlyph(job: job)
                    title
                    Spacer(minLength: 4)
                    ActivityTrailing(job: job)
                }
            }
            ActivityBar(job: job)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.rowFill(dimmed: isLuminanceReduced)))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style.accent.opacity(isLuminanceReduced ? 0.4 : 0.8), lineWidth: 1)
            }
        }
        // Combined, so VoiceOver reads the live countdown text itself ("Dishwasher, Eco 50°, Drying, 42:10") instead
        // of a phrase frozen at the last update.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(job.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ActivityStyle.primaryText)
                .lineLimit(1)
            if !job.status.isEmpty {
                Text(job.status)
                    .font(.caption)
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}
