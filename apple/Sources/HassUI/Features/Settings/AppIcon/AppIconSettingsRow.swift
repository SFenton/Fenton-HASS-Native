import HassCore
import HassDesign
import SwiftUI

/// The Settings row for the app icon: a small preview of the installed icon, "App Icon" and its name, opening
/// ``AppIconPickerSheet``. It sits like the other Settings rows (``SettingsLinkRow``) and hides where the system cannot
/// switch icons.
struct AppIconSettingsRow: View {
    @State private var model: AppIconPickerModel
    @State private var showsPicker = false

    /// Creates the row over the system calls (a fake in tests).
    init(platform: AppIconPlatform) {
        _model = State(initialValue: AppIconPickerModel(platform: platform))
    }

    var body: some View {
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
