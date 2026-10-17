import HassDesign
import SwiftUI

/// A section header over an inset list (`.agents/design/direction-g.md`, Type: 15 Semibold secondary, in Title Case
/// rather than the system's small capitals). In a sheet it takes the sheet's secondary ink; on the wallpaper (the Settings
/// tab) the fixed light ink, because the adaptive secondary measured 3.8:1 there on iPad.
struct SettingsSectionHeader: View {
    var title: String
    @Environment(\.tileSurface) private var surface

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(surface == .page ? HassTokens.Ink.onDarkSecondary : HassTokens.Ink.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}
