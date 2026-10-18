import HassCore
import HassDesign
import SwiftUI

/// The Settings list's Appearance section: the App Icon row under its header. Both vanish where the system cannot
/// switch icons. It owns the model's store (see ``AppIconPickerModelStore`` for why the model is not built in an
/// initialiser).
struct AppIconSettingsSection: View {
    @Environment(\.appIconPlatform) private var platform
    @State private var store = AppIconPickerModelStore()

    var body: some View {
        let model = store.model(for: platform)
        if model.isSupported {
            Section {
                AppIconSettingsRow(model: model)
            } header: {
                SettingsSectionHeader("Appearance")
            }
        }
    }
}
