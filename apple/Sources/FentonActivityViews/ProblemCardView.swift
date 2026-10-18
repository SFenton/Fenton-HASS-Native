import FentonActivityModel
import SwiftUI

/// The problem card, one design for every device (`.agents/platforms/apple/live-activities-per-job.md` §5, §8): a 44 pt
/// solid severity circle with the problem glyph, the device as the title, the problem in the severity's light tint, the
/// instruction in body text, an optional chip, buttons bottom-right (Done last) and the corner mark. Red stopped and needs
/// you; amber carries on.
///
/// VoiceOver reads one phrase, "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap
/// Resume.", then the buttons.
struct ProblemCardView: View {
    let card: ActivityCard
    let problem: ActivityProblem
    var showsMark = true
    @Environment(\.dynamicTypeSize) private var typeSize

    private var colors: ActivityStyle.Severity { ActivityStyle.severity(problem.severity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 14) {
                SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: ActivityStyle.severityCircle)
                text
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.spokenSummary)
            .accessibilityIdentifier("liveactivity.problem")
            ActivityButtons(card: card, buttons: card.buttons, chips: problem.chips)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom)
        )
        .overlay { ContainerRelativeShape().strokeBorder(colors.hairline, lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            if showsMark { CornerMark().padding(.top, 12).padding(.trailing, 14) }
        }
        .accessibilityElement(children: .contain)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The first two lines share the corner with the mark; the instruction starts below it and runs full width.
            VStack(alignment: .leading, spacing: 2) {
                Text(card.deviceTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ActivityStyle.primaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(problem.problem)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.lightText)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
            }
            .padding(.trailing, showsMark ? 48 : 0)
            Text(problem.message)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The solid circle behind a problem's glyph: red when it stopped, amber when it carries on.
struct SeverityCircle: View {
    let glyph: ActivityGlyph
    let severity: ActivityProblem.Severity
    var diameter: CGFloat

    var body: some View {
        Circle()
            .fill(ActivityStyle.severity(severity).circle)
            .frame(width: diameter, height: diameter)
            .overlay { ActivityGlyphImage(glyph: glyph, size: diameter * 0.46, color: .white, weight: .bold) }
            .accessibilityHidden(true)
    }
}
