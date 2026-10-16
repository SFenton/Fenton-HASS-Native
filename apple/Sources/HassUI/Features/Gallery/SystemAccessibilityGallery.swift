#if DEBUG
import HassDesign
import SwiftUI

/// Gallery page that reports the accessibility settings the app actually sees (Reduce Motion, Reduce Transparency,
/// Increase Contrast, Bold Text), so a journey can prove its launch options took effect before it audits
/// (`.agents/testing/apple/accessibility.md`). Launch with `FENTON_GALLERY=system-accessibility`.
struct SystemAccessibilityGallery: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                row("reduceMotion", reduceMotion)
                row("reduceTransparency", reduceTransparency)
                row("increaseContrast", contrast == .increased)
                row("boldText", legibilityWeight == .bold)
            }
            .padding(HassTokens.Spacing.l)
        }
        .navigationTitle("System Accessibility")
    }

    private func row(_ name: String, _ isOn: Bool) -> some View {
        Text("\(name): \(isOn ? "on" : "off")")
            .font(.body)
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HassTokens.Spacing.m)
            .module()
            .accessibilityIdentifier("env.\(name)")
    }
}
#endif
