import FentonActivityModel
import SwiftUI

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
