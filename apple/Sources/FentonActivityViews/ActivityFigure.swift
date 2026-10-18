import FentonActivityModel
import SwiftUI

/// The big figure: a live countdown or count-up, a frozen time, a percentage, a word, or **Complete**.
///
/// `Text(timerInterval:)` and `Text(_:style: .timer)` count on their own with no pushes, which is how a Live Activity shows
/// a ticking time. They take all the width offered and have **no fixed frame** here, so the island's regions size them
/// (spec §8): `lineLimit(1)` with a 0.8 scale floor covers an `H:MM:SS` value in the narrowest region.
struct ActivityFigure: View {
    let card: ActivityCard
    var font: Font
    var alignment: Alignment = .leading

    private var style: ActivityStyle { ActivityStyle(tint: card.tint) }

    var body: some View {
        content
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    private var content: some View {
        switch card.figure {
        case let .countdown(range, showsHours, _):
            Text(timerInterval: range, pauseTime: nil, countsDown: true, showsHours: showsHours)
                .foregroundStyle(ActivityStyle.primaryText)
        case let .countup(start):
            Text(start, style: .timer)
                .foregroundStyle(ActivityStyle.primaryText)
        case let .frozen(seconds):
            Text(ActivityCard.clock(seconds: seconds))
                .foregroundStyle(ActivityStyle.pausedText)
        case let .percent(value):
            Text("\(value)%")
                .foregroundStyle(ActivityStyle.primaryText)
        case let .text(text):
            Text(text)
                .foregroundStyle(ActivityStyle.primaryText)
        case .complete:
            Text("Complete")
                .foregroundStyle(style.accent)
        case .none:
            EmptyView()
        }
    }
}
