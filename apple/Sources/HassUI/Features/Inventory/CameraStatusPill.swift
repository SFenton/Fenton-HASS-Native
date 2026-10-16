import HassDesign
import SwiftUI

/// What the Add Item camera is doing, on a dark capsule over the feed with an inline arc (mockup n6-scan-item:
/// "Looking for a Barcode"). Content over the camera, not navigation, so a material rather than glass.
struct CameraStatusPill: View {
    var text: String

    var body: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            ArcSpinner(.compact, label: text)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, HassTokens.Spacing.m + 2)
        .padding(.vertical, HassTokens.Spacing.s)
        .background(.ultraThinMaterial, in: Capsule())
        // A dark material whatever the sheet's appearance: the text over it is white.
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("scan.cameraActivity")
    }
}
