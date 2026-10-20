import HassCore
import HassDesign
import SwiftUI

/// One person: a monogram in their colour, their name and Home, Away or the zone.
struct PersonRow: View {
    var person: ProfileSummary.Person
    @ScaledMetric(relativeTo: .body) private var monogramSize: CGFloat = 36

    /// A resident's monogram colour: their chore family (the same blue and magenta their chores carry); a guest's is a
    /// neutral grey (white initials on it measure 5.7:1).
    static func fill(for person: ProfileSummary.Person) -> Color {
        switch person.resident {
        case .stephen: ColorFamily.choreStephen.fill ?? HassTokens.Ink.actionFill
        case .steph: ColorFamily.choreSteph.fill ?? HassTokens.Ink.actionFill
        case nil: Color(white: 0.4)
        }
    }

    var body: some View {
        HStack(spacing: HassTokens.Spacing.m) {
            Text(ProfileButton.initials(person.name) ?? "?")
                .font(.system(size: monogramSize * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: monogramSize, height: monogramSize)
                .background(Self.fill(for: person), in: Circle())
                .accessibilityHidden(true)
            Text(person.name)
                .foregroundStyle(HassTokens.Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(person.stateText)
                .foregroundStyle(person.isHome ? HassTokens.Ink.success : HassTokens.Surface.secondaryInSheet)
        }
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.person.\(person.id)")
    }
}
