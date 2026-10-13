import HassCore
import HassDesign
import SwiftUI

/// A section title inside a room sheet (web `RoomSectionHeader`): a heading for VoiceOver's rotor.
struct RoomOverviewHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, HassTokens.Spacing.s)
            .accessibilityAddTraits(.isHeader)
    }
}
