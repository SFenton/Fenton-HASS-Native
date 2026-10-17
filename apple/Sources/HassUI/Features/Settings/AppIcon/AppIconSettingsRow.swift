import HassCore
import HassDesign
import SwiftUI

/// The Settings row for the app icon: a small preview of the installed icon, "App Icon" and its name, opening
/// ``AppIconPickerSheet``. It sits like the other Settings rows (``SettingsLinkRow``) and hides where the system cannot
/// switch icons.
struct AppIconSettingsRow: View {
    @Environment(\.appIconPlatform) private var platform
    @State private var store = AppIconPickerModelStore()
    @State private var showsPicker = false

    var body: some View {
        let model = store.model(for: platform)
        if model.isSupported {
            Button { showsPicker = true } label: {
                SettingsLinkRow(title: Self.title, subtitle: model.selected.displayName, symbol: "app.fill", appIcon: model.selected)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.appIcon")
            .accessibilityHint("Opens the icons you can use on the Home Screen.")
            .sheet(isPresented: $showsPicker) {
                AppIconPickerSheet(model: model)
                    .hassSheet(.form)
            }
        }
    }

    /// The row's title.
    static let title = "App Icon"
}
