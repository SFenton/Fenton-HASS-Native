import FentonActivityModel
import SwiftUI

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
