import HassCore
import HassDesign
import SwiftUI

/// The Settings list's Appearance section: Background Blur (a slider and its reset) and the App Icon row (which
/// vanishes where the system cannot switch icons). The section owns the App Icon model's store (see
/// ``AppIconPickerModelStore`` for why the model is not built in an initialiser).
struct AppearanceSettingsSection: View {
    @Environment(\.appIconPlatform) private var platform
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.tileSurface) private var surface
    @Environment(HouseBackdropStore.self) private var backdrop: HouseBackdropStore?
    @State private var store = AppIconPickerModelStore()
    /// The setting where there is no backdrop store (the debug galleries): the same saved value, nothing to re-render.
    @State private var standalone = BackdropBlurSettings()

    var body: some View {
        let model = store.model(for: platform)
        Section {
            BackdropBlurRows(settings: backdrop?.blur ?? standalone)
            if model.isSupported {
                AppIconSettingsRow(model: model)
            }
        } header: {
            SettingsSectionHeader("Appearance")
        } footer: {
            Text(BackdropBlurRows.footer(reduceTransparency: reduceTransparency))
                .foregroundStyle(surface == .page ? HassTokens.Ink.onDarkSecondary : HassTokens.Ink.secondary)
        }
    }
}

/// Background Blur: a 0 to 100% slider (``PercentSliderRow``, the app's one slider-with-value row) for how soft the
/// house photo behind every page is, and Reset to Default. The default, 50%, is the web dashboard's blur on screen
/// (``BackdropBlur``). Dragging previews live: the backdrop store renders the latest value as fast as a render
/// finishes (``HouseBackdropStore``), keeping the previous picture up meanwhile.
struct BackdropBlurRows: View {
    @Bindable var settings: BackdropBlurSettings

    var body: some View {
        PercentSliderRow(Self.title, value: $settings.sliderValue, identifier: "settings.backdropBlur")
        Button("Reset to Default") { settings.reset() }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
            .disabled(settings.isDefault)
            .accessibilityHint("Sets the background blur to match the web dashboard.")
            .accessibilityIdentifier("settings.backdropBlur.reset")
    }

    /// The slider's name, which VoiceOver also reads.
    static let title = "Background Blur"

    /// The section's footer: what the slider does, or why it shows nothing.
    static func footer(reduceTransparency: Bool) -> String {
        reduceTransparency
            ? "Reduce Transparency is on, so pages use a plain background and the blur has nothing to soften."
            : "How soft the house photo behind every page is. The default matches the web dashboard; less blur can make text harder to read."
    }
}
