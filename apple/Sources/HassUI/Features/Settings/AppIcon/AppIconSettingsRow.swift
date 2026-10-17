import HassCore
import HassDesign
import SwiftUI

/// The Settings row for the app icon: a small preview of the installed icon, "App Icon" and its name, opening
/// ``AppIconPickerSheet``. It sits like the other Settings rows (``SettingsLinkRow``), in ``AppIconSettingsSection``.
struct AppIconSettingsRow: View {
    let model: AppIconPickerModel
    @State private var showsPicker = false

    var body: some View {
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

    /// The row's title.
    static let title = "App Icon"
}
