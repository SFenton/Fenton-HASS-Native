import HassDesign
import SwiftUI

/// A short single choice, 2 to 4 options (direction G, Controls: "2–4 short options use the system segmented
/// control"): a segmented control, or a menu that names the choice at accessibility text sizes, where segments
/// cannot grow (HIG: Segmented controls). Choosing sends at once. Nothing is selected while the device reports a
/// value outside the options (a mist level between presets).
///
/// XCUITest finds it by `identifier` and each option as a button named by its title.
public struct SegmentedChoice<Option: Hashable>: View {
    var label: String
    var options: [Option]
    var title: (Option) -> String
    var selection: Option?
    var identifier: String
    var select: (Option) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Creates the control.
    public init(label: String, options: [Option], title: @escaping (Option) -> String, selection: Option?,
                identifier: String, select: @escaping (Option) -> Void) {
        self.label = label
        self.options = options
        self.title = title
        self.selection = selection
        self.identifier = identifier
        self.select = select
    }

    public var body: some View {
        // A derived binding: the view holds no state; the device's reported value is the selection.
        let binding = Binding<Option?>(get: { selection }, set: { option in
            if let option, option != selection { select(option) }
        })
        let picker = Picker(label, selection: binding) {
            ForEach(options, id: \.self) { option in
                Text(title(option)).tag(Optional(option))
            }
        }
        .accessibilityIdentifier(identifier)
        if typeSize.isAccessibilitySize {
            picker
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
        } else {
            picker
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
        }
    }
}

