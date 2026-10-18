import FentonActivityModel
import SwiftUI

/// The job card (fan, dishwasher, dryer, washer, vacuum room, hot flash): a 64 pt ring with the glyph, a 17 pt title over a
/// 28 pt figure, up to two buttons bottom-right, and the corner mark top-right
/// (`.agents/platforms/apple/live-activities-per-job.md` §8). The title is one line; the figure is one line; neither
/// has a subtitle except the hot flash's "Your side".
///
/// Height is at most 160 pt at the default text size (`LiveActivityJourneyTests`); at accessibility sizes the figure
/// wraps under the title and the buttons stack.
struct JobCardView: View {
    let card: ActivityCard
    var showsMark = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ActivityRing(card: card)
                    text
                }
            } else {
                HStack(spacing: 16) {
                    ActivityRing(card: card)
                    text
                }
                .frame(minHeight: card.isComplete ? 84 : 0)
            }
            ActivityButtons(card: card, buttons: card.buttons)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if showsMark { CornerMark().padding(.top, 12).padding(.trailing, 14) }
        }
        .accessibilityElement(children: .contain)
    }

    /// Title, optional short line, and the figure (or a notice). One accessibility element, so VoiceOver reads the title,
    /// the line and the live figure together.
    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ActivityStyle.primaryText)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .accessibilityLabel(card.spokenTitle)
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(ActivityStyle.secondaryText)
                    .lineLimit(1)
            }
            if let notice = card.notice {
                Text(notice)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ActivityStyle.noticeText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("liveactivity.notice")
            } else {
                ActivityFigure(card: card, font: .system(size: 28, weight: .semibold))
            }
        }
        .padding(.trailing, showsMark ? 48 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liveactivity.text")
    }
}
