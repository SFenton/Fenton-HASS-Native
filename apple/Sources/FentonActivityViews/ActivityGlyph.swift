import FentonActivityModel
import SwiftUI

/// A job's glyph in a tinted circle.
struct ActivityGlyph: View {
    let job: ActivityJob
    var size: CGFloat = 26
    /// The glyph grows with the text (capped, so it never crowds the row), like the words beside it.
    @ScaledMetric(relativeTo: .subheadline) private var textScale = 1

    var body: some View {
        let style = ActivityStyle(tint: job.tint)
        let size = size * min(textScale, 1.8)
        Image(systemName: job.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(style.accent)
            .frame(width: size, height: size)
            .background(Circle().fill(style.rowFill()))
            .accessibilityHidden(true)
    }
}
