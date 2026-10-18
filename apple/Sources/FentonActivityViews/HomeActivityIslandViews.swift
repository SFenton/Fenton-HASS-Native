import FentonActivityModel
import SwiftUI

/// The Dynamic Island's regions for one activity (`.agents/platforms/apple/live-activities-per-job.md` §8). The widget
/// extension places each in `DynamicIsland { ... }`; the gallery and the tests draw them in a black capsule.
///
/// Only small things sit beside the camera: the ring (or severity circle) on the leading side and the figure at 22 pt on the
/// trailing side, with **no fixed frames**. The system sizes the regions for each phone's camera, so nothing here measures
/// a device. The title and the buttons go below the camera, in the full width. The centre region stays empty.
public enum HomeActivityIsland {
    /// Compact, leading: the 26 pt ring with the glyph; a problem shows the severity circle.
    public struct CompactLeading: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            Group {
                if let problem = card.problem {
                    SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 24)
                } else {
                    ActivityRing(card: card, diameter: 26)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.problem == nil ? card.title : card.spokenSummary)
        }
    }

    /// Compact, trailing: the figure at 15 pt, monospaced; a problem shows one word ("Stuck", "Refill water"). In a limited
    /// width (`isDynamicIslandLimitedInWidth`, iOS 27) it is empty and only the leading side shows.
    public struct CompactTrailing: View {
        let card: ActivityCard
        let isLimitedWidth: Bool

        public init(card: ActivityCard, isLimitedWidth: Bool = false) {
            self.card = card
            self.isLimitedWidth = isLimitedWidth
        }

        public var body: some View {
            if isLimitedWidth {
                EmptyView()
            } else if let problem = card.problem {
                Text(problem.compactLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle.severity(problem.severity).lightText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if card.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle(tint: card.tint).accent)
                    .accessibilityLabel("Complete")
            } else {
                ActivityFigure(card: card, font: .subheadline.weight(.semibold), alignment: .trailing)
            }
        }
    }

    /// Minimal: the ring alone, which fits a 28 pt circle; a problem shows the severity circle.
    public struct Minimal: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            Group {
                if let problem = card.problem {
                    SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 24)
                } else {
                    ActivityRing(card: card, diameter: 24)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.problem == nil ? card.title : card.spokenSummary)
        }
    }

    /// Expanded, leading (beside the camera): the 34 pt ring, or the 32 pt severity circle.
    public struct ExpandedLeading: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            Group {
                if let problem = card.problem {
                    SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 32)
                } else {
                    ActivityRing(card: card, diameter: 34)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Expanded, trailing (beside the camera): the figure at 22 pt semibold, monospaced, one line, scaling down to 80%, with
    /// no fixed width. A problem says "Needs help" or "Attention" instead.
    public struct ExpandedTrailing: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            if let problem = card.problem {
                Text(card.problemIslandLabel ?? problem.severity.islandLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle.severity(problem.severity).lightText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if let notice = card.notice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ActivityStyle.noticeText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ActivityFigure(card: card, font: .title2.weight(.semibold), alignment: .trailing)
                    .accessibilityLabel(card.spokenFigure ?? "")
            }
        }
    }

    /// Expanded, bottom (below the camera, in the full width): the title or headline at 17 pt on one line, the problem line
    /// under it on a problem card, and up to two buttons (or "Stopping…").
    public struct ExpandedBottom: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.problem == nil ? card.title : card.deviceTitle)
                        .font(.headline)
                        .foregroundStyle(ActivityStyle.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let problem = card.problem {
                        Text(problem.problem)
                            .font(.footnote)
                            .foregroundStyle(ActivityStyle.severity(problem.severity).lightText)
                            .lineLimit(1)
                    } else if let detail = card.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(ActivityStyle.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                ActivityButtons(card: card, buttons: card.islandButtons)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
