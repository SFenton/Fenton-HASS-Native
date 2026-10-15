import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One custom light's sheet (web `LightMoreInfoSheet.tsx`): its brightness tile and, for color lights, the color,
/// Reset to Warm White and Apply to All Lights rows, and one swatch per other light to copy that light's color
/// (direction G, n4 custom light sheet).
///
/// The web draws a hue wheel and RGB sliders; the app uses the system color picker instead (HIG: Color wells),
/// which offers the same wheel, sliders and eyedropper and is familiar to VoiceOver users.
struct CustomLightSheet: View {
    var light: CustomLightsConfig.Light
    var store: EntityStore
    var caller: any HassServiceCalling
    @Environment(\.dismiss) private var dismiss
    @State private var pendingColor: Task<Void, Never>?
    @ScaledMetric(relativeTo: .subheadline) private var minSwatchWidth: CGFloat = 76

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
            .modalChrome()
            .navigationTitle(light.title)
            .sheetSubtitle(Self.subtitle(state))
            .inlineNavigationTitle()
            .toolbar { SheetCloseItem { dismiss() } }
        }
        .tint(HassTokens.Ink.action)
    }

    /// "On · 80%", "Off" or "Unavailable".
    static func subtitle(_ state: EntityState?) -> String {
        guard let state, !state.isUnavailable else { return "Unavailable" }
        let percent = LightControl.percent(of: state)
        return percent > 0 ? "On · \(percent)%" : "Off"
    }

    // MARK: - Color

    /// The color, Reset to Warm White and Apply to All Lights, as rows of one inset group on the sheet.
    private func colorSection(rgb: CustomLightsConfig.RGB?, unavailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ColorPicker(selection: colorBinding(rgb), supportsOpacity: false) {
                Label("Color", systemImage: "paintpalette")
                    .foregroundStyle(HassTokens.Ink.primary)
            }
            .padding(.horizontal, HassTokens.Spacing.l)
            .frame(minHeight: 52)
            .disabled(unavailable)
            .accessibilityIdentifier("customLight.color")
            Divider().padding(.leading, HassTokens.Spacing.l)
            actionRow("Reset to Warm White", symbol: "arrow.counterclockwise", id: "customLight.reset") {
                caller.fire(CustomLightsConfig.reset(light.entityId))
            }
            .disabled(unavailable)
            Divider().padding(.leading, HassTokens.Spacing.l)
            actionRow("Apply to All Lights", symbol: "lightbulb.2", id: "customLight.applyAll") {
                if let rgb { caller.fire(CustomLightsConfig.setColor(rgb, on: CustomLightsConfig.groupEntityId)) }
            }
            .disabled(unavailable || rgb == nil)
        }
        .background(HassTokens.Surface.sheetCell, in: RoundedRectangle(cornerRadius: HassTokens.Radius.module, style: .continuous))
    }

    /// A row that runs an action, its title in the tint (direction G: Reset is a list row, not a grey button).
    private func actionRow(_ title: String, symbol: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            WrappingRowLabel(title: title, symbol: symbol)
                .padding(.horizontal, HassTokens.Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActionRowStyle())
        .accessibilityLabel(title)
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
            RoomSectionHeader(title: "Copy Color From", inSheet: true)
            DynamicGridLayout(minCellWidth: minSwatchWidth, maxColumns: 4, spacing: HassTokens.Spacing.s, equalRowHeights: true) {
                ForEach(others) { other in
                    let state = store.entity(other.entityId).state
                    OtherLightSwatch(light: other, rgb: CustomLightsConfig.RGB(entity: state), isUnavailable: state?.isUnavailable ?? true) { color in
                        caller.fire(CustomLightsConfig.setColor(color, on: light.entityId))
                    }
                }
            }
            .padding(HassTokens.Spacing.m)
            .background(HassTokens.Surface.sheetCell, in: RoundedRectangle(cornerRadius: HassTokens.Radius.module, style: .continuous))
        }
    }

    private func send(_ command: LightControl.Command) {
        Task { try? await caller.callService(command.domain, command.service, data: command.serviceData) }
    }
}

/// Tint text that keeps its contrast: the tint while enabled, the sheet's secondary label while disabled.
private struct ActionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionRowBody(configuration: configuration)
    }

    private struct ActionRowBody: View {
        var configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? HassTokens.Ink.action : HassTokens.Surface.secondaryInSheet)
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

/// Copies another light's color onto the open light (web `OtherLightButton`): a circle of its color with its name
/// under it, or an empty ring and "Off" (or "Unavailable") while it has no color.
struct OtherLightSwatch: View {
    var light: CustomLightsConfig.Light
    var rgb: CustomLightsConfig.RGB?
    var isUnavailable = false
    var apply: (CustomLightsConfig.RGB) -> Void
    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 48

    var body: some View {
        Button {
            if let rgb { apply(rgb) }
        } label: {
            VStack(spacing: HassTokens.Spacing.xs) {
                Group {
                    if let rgb {
                        Circle().fill(Color(rgb: rgb))
                    } else {
                        Circle().strokeBorder(HassTokens.Surface.secondaryInSheet, lineWidth: 1.5)
                    }
                }
                .frame(width: max(diameter, HassTokens.minTarget), height: max(diameter, HassTokens.minTarget))
                Text(light.title)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if rgb == nil {
                    Text(isUnavailable ? "Unavailable" : "Off").font(.footnote)
                }
            }
            .foregroundStyle(HassTokens.Surface.secondaryInSheet)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apply \(light.title) Color")
        .accessibilityValue(rgb == nil ? (isUnavailable ? "Unavailable" : "Off") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("customLight.other.\(light.entityId)")
        // Disabled without dimming, outside the combined element so VoiceOver reads it dimmed (see GlassTile); the
        // name and status keep their contrast.
        .disabled(rgb == nil)
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
