import HassCore
import HassDesign
import SwiftUI

/// Quick Links as the floating glass circle on iPad and the unfolded Duo (regular width; direction G mockup
/// n1-ipad-home): 56 pt, bottom trailing, on Liquid Glass (iOS 26) or a thin-material circle. It is a navigation
/// control, so glass is right for it (HIG Materials: Liquid Glass belongs to the navigation layer). It reuses the
/// toolbar button's identifier so journeys find Quick Links the same way on every device.
struct FloatingQuickLinksButton: View {
    /// The circle's diameter (HIG Buttons: at least 44 pt).
    static let diameter: CGFloat = 56

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: QuickLinksButton.symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: Self.diameter, height: Self.diameter)
                .navigationGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(QuickLinks.title)
        .accessibilityIdentifier("quickLinks.open")
    }
}
