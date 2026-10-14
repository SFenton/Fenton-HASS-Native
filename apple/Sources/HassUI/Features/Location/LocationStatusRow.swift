import HassCore
import HassDesign
import SwiftUI

/// "Location Access" and its value in an inset cell, read as one element; stacks the value under the label when
/// they don't fit side by side (AX sizes, the folded Duo).
struct LocationStatusRow: View {
    var permission: LocationPermission

    var body: some View {
        let value = LocationPermissionCopy.status(permission)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HassTokens.Spacing.m) {
                label
                Spacer(minLength: 0)
                Text(value).foregroundStyle(valueColor)
            }
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                label
                Text(value).foregroundStyle(valueColor)
            }
        }
        .font(.body)
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(LocationPermissionView.cellColor, in: .rect(cornerRadius: HassTokens.Radius.tile))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Location Access")
        .accessibilityValue(value)
        .accessibilityIdentifier("location.status")
    }

    private var label: some View {
        Text("Location Access").foregroundStyle(HassTokens.Ink.primary)
    }

    /// Off reads red and Approximate amber; the words carry the meaning too.
    private var valueColor: Color {
        switch permission.stage {
        case .denied: HassTokens.Ink.danger
        case .reducedAccuracy: HassTokens.Ink.warning
        case .notDetermined, .whenInUse, .always: HassTokens.Ink.secondary
        }
    }
}
