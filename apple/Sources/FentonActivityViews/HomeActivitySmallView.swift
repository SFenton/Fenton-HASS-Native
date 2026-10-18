import FentonActivityModel
import SwiftUI

/// The Apple Watch Smart Stack and CarPlay presentation (`.small` supplemental family, iOS 18): the glyph, the title and the
/// figure (or the headline of a card with no figure). No controls: buttons do nothing there until a device check says otherwise
/// (`.agents/platforms/apple/live-activities-per-job.md` §8).
public struct HomeActivitySmallView: View {
    private let card: ActivityCard

    /// Creates the view.
    public init(card: ActivityCard) { self.card = card }

    public var body: some View {
        HStack(spacing: 8) {
            if let problem = card.problem {
                SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 30)
            } else if card.showsRing {
                ActivityRing(card: card, diameter: 32)
            } else {
                ActivityHeaderGlyph(card: card, size: 26)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(card.problem == nil ? card.title : card.deviceTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ActivityStyle.primaryText)
                    .lineLimit(1)
                if let problem = card.problem {
                    Text(problem.problem)
                        .font(.caption)
                        .foregroundStyle(ActivityStyle.severity(problem.severity).lightText)
                        .lineLimit(1)
                } else if let bigLine = card.bigLine {
                    Text(bigLine)
                        .font(.headline)
                        .foregroundStyle(ActivityStyle.primaryText)
                        .lineLimit(1)
                } else {
                    ActivityFigure(card: card, size: 17, relativeTo: .headline)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
