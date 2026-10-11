import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One custom light's sheet (web `LightMoreInfoSheet.tsx`): its brightness tile and, for color lights, the color,
/// Reset, Apply to All Lights, and one button per other light to copy that light's color.
///
/// The web draws a hue wheel and RGB sliders; the app uses the system color picker instead (HIG: Color wells),
/// which offers the same wheel, sliders and eyedropper and is familiar to VoiceOver users.
struct CustomLightSheet: View {
    var light: CustomLightsConfig.Light
    var store: EntityStore
    var caller: any HassServiceCalling
    @Environment(\.dismiss) private var dismiss
    @State private var pendingColor: Task<Void, Never>?
    @ScaledMetric(relativeTo: .subheadline) private var minSwatchWidth: CGFloat = 64

    var body: some View {
        let state = store.entity(light.entityId).state
        let rgb = CustomLightsConfig.RGB(entity: state)
        let others = CustomLightsConfig.lights.filter { $0 != light }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
                    BrightnessTile(
                        title: light.title,
                        tint: HassTokens.Tint.light,
                        fillTint: rgb.map(Color.init(rgb:)),
                        percent: LightControl.percent(of: state),
                        isUnavailable: state?.isUnavailable ?? true,
                        onPower: { send(LightControl.power(light.entityId, on: $0)) },
                        onBrightness: { send(LightControl.brightness(light.entityId, percent: Double($0))) }
                    )
                    .accessibilityIdentifier("customLight.brightness")
                    if CustomLightsConfig.supportsColor(state) {
                        colorSection(rgb: rgb, unavailable: state?.isUnavailable ?? true)
                        if !others.isEmpty { otherLights(others) }
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(HassTokens.Spacing.l)
            }
            .navigationTitle(light.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(HassTokens.Ink.action)
    }

    // MARK: - Color

    private func colorSection(rgb: CustomLightsConfig.RGB?, unavailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            ColorPicker(selection: colorBinding(rgb), supportsOpacity: false) {
                Label("Color", systemImage: "paintpalette")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
            }
            .frame(minHeight: HassTokens.minTarget)
            .disabled(unavailable)
            .accessibilityIdentifier("customLight.color")
            HStack(spacing: HassTokens.Spacing.m) {
                actionButton("Reset", symbol: "arrow.counterclockwise", id: "customLight.reset") {
                    caller.fire(CustomLightsConfig.reset(light.entityId))
                }
                actionButton("Apply to All Lights", symbol: "lightbulb.2", id: "customLight.applyAll", disabled: rgb == nil) {
                    if let rgb { caller.fire(CustomLightsConfig.setColor(rgb, on: CustomLightsConfig.groupEntityId)) }
                }
            }
            .disabled(unavailable)
        }
    }

    private func actionButton(_ title: String, symbol: String, id: String, disabled: Bool = false,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Label ink, not the tint: tinted text on the bordered fill measured under 4.5:1.
            Label(title, systemImage: symbol)
                .foregroundStyle(disabled ? HassTokens.Ink.secondary : HassTokens.Ink.primary)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget - 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(disabled)
        .accessibilityIdentifier(id)
    }

    /// Sends a picked color once the picker settles, so dragging across the wheel doesn't flood the light.
    private func colorBinding(_ rgb: CustomLightsConfig.RGB?) -> Binding<Color> {
        Binding(
            get: { rgb.map(Color.init(rgb:)) ?? .white },
            set: { color in
                guard let picked = CustomLightsConfig.RGB(color: color), picked != rgb else { return }
                pendingColor?.cancel()
                pendingColor = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    caller.fire(CustomLightsConfig.setColor(picked, on: light.entityId))
                }
            }
        )
    }

    // MARK: - Other lights

    private func otherLights(_ others: [CustomLightsConfig.Light]) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            Text("Other Lights")
                .font(.headline)
                .foregroundStyle(HassTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)
            DynamicGridLayout(minCellWidth: minSwatchWidth, maxColumns: 7, spacing: HassTokens.Spacing.s) {
                ForEach(others) { other in
                    OtherLightSwatch(light: other, rgb: CustomLightsConfig.RGB(entity: store.entity(other.entityId).state)) { color in
                        caller.fire(CustomLightsConfig.setColor(color, on: light.entityId))
                    }
                }
            }
        }
    }

    private func send(_ command: LightControl.Command) {
        Task { try? await caller.callService(command.domain, command.service, data: command.serviceData) }
    }
}

/// Copies another light's color onto the open light (web `OtherLightButton`); disabled while it has no color.
struct OtherLightSwatch: View {
    var light: CustomLightsConfig.Light
    var rgb: CustomLightsConfig.RGB?
    var apply: (CustomLightsConfig.RGB) -> Void

    var body: some View {
        Button {
            if let rgb { apply(rgb) }
        } label: {
            Image(systemName: "lamp.floor.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1)
                .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget + 12)
                .background(rgb.map(Color.init(rgb:)) ?? Color.secondary.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(rgb == nil)
        .accessibilityLabel("Apply \(light.title) Color")
        .accessibilityIdentifier("customLight.other.\(light.entityId)")
    }
}

extension HassServiceCalling {
    /// Fire-and-forget call for view actions; failures surface through the entity's state.
    func fire(_ serviceCall: ServiceCall) {
        Task { try? await call(serviceCall) }
    }
}

extension CustomLightsConfig.RGB {
    /// A picked color in sRGB, rounded to 0...255 per channel; `nil` when it can't be converted.
    init?(color: Color) {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #else
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let red = srgb.redComponent, green = srgb.greenComponent, blue = srgb.blueComponent
        #endif
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        self.init(channel(red), channel(green), channel(blue))
    }
}
