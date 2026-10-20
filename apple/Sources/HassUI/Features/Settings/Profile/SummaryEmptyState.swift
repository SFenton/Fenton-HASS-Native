import HassCore
import HassDesign
import SwiftUI

/// An empty tab: a glyph, the title and what it means, centred (web `EmptyState layout="modal"`).
struct SummaryEmptyState: View {
    var copy: ProfileSummary.EmptyCopy
    var symbol: String
    var identifier: String

    var body: some View {
        ContentUnavailableView {
            Label(copy.title, systemImage: symbol)
        } description: {
            Text(copy.description)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HassTokens.Spacing.xl)
        .accessibilityIdentifier(identifier)
    }
}
