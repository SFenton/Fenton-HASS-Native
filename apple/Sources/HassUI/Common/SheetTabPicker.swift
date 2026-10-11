import HassDesign
import SwiftUI

/// The segmented tab control at the top of a tabbed sheet (media remote, thermostat); a menu at accessibility
/// text sizes, where segments can't grow (HIG: Segmented controls).
struct SheetTabPicker<Tab: Hashable & Identifiable>: View {
    var tabs: [Tab]
    /// Spoken name of the control, e.g. `Thermostat sections`.
    var label: String
    var title: (Tab) -> String
    @Binding var selection: Tab
    var identifier: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let picker = Picker(label, selection: $selection) {
            ForEach(tabs) { Text(title($0)).tag($0) }
        }
        .accessibilityIdentifier(identifier)
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu).frame(minHeight: HassTokens.minTarget)
        } else {
            picker.pickerStyle(.segmented).labelsHidden()
        }
    }
}
