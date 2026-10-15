import HassDesign
import SwiftUI

/// One "how it works" point on the location permission screen: a symbol, a title and a line of detail, read as
/// one element.
struct LocationPointRow: View {
    var point: LocationPermissionCopy.Point
    @ScaledMetric(relativeTo: .title2) private var symbolWidth: CGFloat = 32

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HassTokens.Spacing.m) {
            Image(systemName: point.symbol)
                .font(.title2)
                .foregroundStyle(HassTokens.Ink.action)
                .frame(width: symbolWidth)
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                Text(point.title)
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                Text(point.detail)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("location.point.\(point.symbol)")
    }
}
