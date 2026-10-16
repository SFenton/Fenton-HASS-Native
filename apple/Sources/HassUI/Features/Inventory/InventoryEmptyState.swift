import HassDesign
import SwiftUI

/// An inventory page's empty or error state on the wallpaper (mockup n6-inventory-empty): a basket (or a warning
/// triangle), the title in 22 Bold and the description in secondary, centred. Errors add Try Again.
///
/// Plain wrapping text rather than `ContentUnavailableView` in a list row, whose title the accessibility audit
/// reported as clipped at large text sizes.
struct InventoryEmptyState: View {
    var title: String
    var description: String
    /// The page failed to load: a warning glyph and Try Again.
    var isError: Bool
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: isError ? "exclamationmark.triangle" : "basket")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(HassTokens.Ink.secondary)
                .padding(.bottom, HassTokens.Spacing.xs)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .foregroundStyle(HassTokens.Ink.secondary)
            if isError {
                PrimaryButton("Try Again", action: onRetry)
                    .frame(maxWidth: 320)
                    .padding(.top, HassTokens.Spacing.m)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, HassTokens.Spacing.xl + HassTokens.Spacing.s)
        .padding(.vertical, HassTokens.Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory.empty")
    }
}
