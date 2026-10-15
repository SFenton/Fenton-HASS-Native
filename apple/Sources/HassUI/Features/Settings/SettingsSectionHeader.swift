import HassDesign
import SwiftUI

/// A section header over an inset list in a sheet (`.agents/design/direction-g.md`, Type: 15 Semibold secondary,
/// in Title Case rather than the system's small capitals).
struct SettingsSectionHeader: View {
    var title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        FormHeader(title)
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
    }
}
