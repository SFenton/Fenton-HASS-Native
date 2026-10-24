import HassCore
import HassDesign
import SwiftUI

/// The Custom Lights page (web `CustomLightsPage.tsx`; spec `.agents/pages/custom-lights/spec.md`).
///
/// Manual control of the front yard lights; while it is on, the lighting mode; in Custom mode, a brightness tile
/// per light (tap opens its color sheet) and Reset All Lights.
public struct CustomLightsScreen: View {
    private let store: EntityStore
    private let caller: any HassServiceCalling
    @State private var picker = false
    @State private var detail: CustomLightsConfig.Light?
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 150

    /// Creates the page.
    /// - Parameters:
    ///   - store: Live entity state.
    ///   - caller: Where service calls go (the connection, or a recorder in the gallery and tests).
    ///   - openLight: A light whose sheet opens at once (gallery and journeys).
    ///   - openPicker: Opens the lighting mode picker at once (gallery and journeys).
    public init(store: EntityStore, caller: any HassServiceCalling, openLight: CustomLightsConfig.Light? = nil, openPicker: Bool = false) {
        self.store = store
        self.caller = caller
        _detail = State(initialValue: openLight)
        _picker = State(initialValue: openPicker)
    }

    public var body: some View {
        let manual = store.entity(CustomLightsConfig.manualControlEntityId).state
        let select = store.entity(CustomLightsConfig.modeEntityId).state
        let manualOn = manual?.state == "on"
        let mode = CustomLightsConfig.mode(select)
        let showsLights = manualOn && mode == CustomLightsConfig.customMode
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                RoomSectionHeader(title: CustomLightsConfig.frontYardTitle)
                ModuleList {
                    ManualControlRow(isOn: manualOn, isUnavailable: manual?.isUnavailable ?? true) {
                        send(CustomLightsConfig.setManualControl(on: $0))
                    }
                    if manualOn {
                        LightingModeButton(mode: mode, swatch: swatch(mode)) { picker = true }
                    }
                }
                if showsLights {
                    DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
                        ForEach(CustomLightsConfig.lights) { light in
                            CustomLightTile(light: light, state: store.entity(light.entityId).state, caller: caller) { detail = light }
                        }
                    }
                    .equalHeightTiles()
                    // Reset is a list row, not a grey button (direction G, Sheets and Primary buttons).
                    Button {
                        send(CustomLightsConfig.reset())
                    } label: {
                        WrappingRowLabel(title: "Reset All Lights", symbol: "arrow.counterclockwise")
                            .foregroundStyle(HassTokens.Ink.action)
                            .padding(.horizontal, HassTokens.Spacing.l)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .module()
                    .accessibilityLabel("Reset All Lights")
                    .accessibilityIdentifier("customLights.resetAll")
                }
            }
            .motionSafeAnimation(MotionTokens.standard, value: manualOn)
            .motionSafeAnimation(MotionTokens.standard, value: showsLights)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, HassTokens.Spacing.l)
            .padding(.vertical, HassTokens.Spacing.m)
        }
        .tint(HassTokens.Ink.action)
        .scrollTelemetry("Custom Lights")
        .accessibilityIdentifier("customLights.scroll")
        .navigationTitle("Custom Lights")
        .sheet(isPresented: $picker) {
            OptionPickerSheet(
                title: CustomLightsConfig.lightingModeTitle,
                options: CustomLightsConfig.modes(select).map { .init(value: $0, swatch: swatch($0).map(Color.init(rgb:))) },
                selected: mode, identifierPrefix: "customLights.mode"
            ) { option in
                send(CustomLightsConfig.selectMode(option))
            }
            .galleryLastCallBanner()
            .hassSheet(.form)
        }
        .sheet(item: $detail) { light in
            CustomLightSheet(light: light, store: store, caller: caller)
                .galleryLastCallBanner()
                .hassSheet(.page)
        }
    }

    /// The swatch for a mode; Custom shows the lights' live colors.
    private func swatch(_ mode: String) -> [CustomLightsConfig.RGB] {
        let colors = CustomLightsConfig.lights.compactMap { CustomLightsConfig.RGB(entity: store.entity($0.entityId).state) }
        return CustomLightsConfig.swatch(for: mode, custom: colors)
    }

    private func send(_ call: ServiceCall) { caller.fire(call) }
}

// MARK: - Front yard rows

/// The manual control switch, the first row of the Front Yard list (direction G: switches only in list rows).
struct ManualControlRow: View {
    static let title = "Manually Control Front Yard Lights"
    var isOn: Bool
    var isUnavailable: Bool
    var set: (Bool) -> Void

    var body: some View {
        ModuleRow(Self.title, symbol: "lightbulb.2", glyph: isOn ? ColorFamily.lights.glyph : ColorFamily.lights.offGlyph,
                  glyphOpacity: isUnavailable ? 0.5 : 1) {
            Toggle(Self.title, isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .disabled(isUnavailable)
                .accessibilityIdentifier("customLights.manual")
        }
    }
}

/// The Lighting Mode row: palette icon, then the mode's swatch and name in the tint with the pop-up chevrons
/// (web `modeSelect`). It opens the lighting modes.
struct LightingModeButton: View {
    var mode: String
    var swatch: [CustomLightsConfig.RGB]
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ModuleRow(CustomLightsConfig.lightingModeTitle, symbol: "paintpalette") {
                HStack(spacing: HassTokens.Spacing.s) {
                    GradientSwatch(colors: swatch.map(Color.init(rgb:)))
                        .stateColorTransition("LightingModeButton", value: swatch)
                    Text(mode)
                        .foregroundStyle(HassTokens.Ink.action)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HassTokens.Ink.action)
                }
            }
        }
        .buttonStyle(ModuleRowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CustomLightsConfig.lightingModeTitle)
        .accessibilityValue(mode)
        .accessibilityHint("Opens the lighting modes.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("customLights.mode")
    }
}

// MARK: - Lights

/// A custom light's brightness tile; tap opens its sheet (web `tapAction: 'more-info'`), drag sets brightness.
struct CustomLightTile: View {
    var light: CustomLightsConfig.Light
    var state: EntityState?
    var caller: any HassServiceCalling
    var open: () -> Void

    var body: some View {
        BrightnessTile(
            title: light.title,
            tint: HassTokens.Tint.light,
            fillTint: CustomLightsConfig.RGB(entity: state).map(Color.init(rgb:)),
            percent: LightControl.percent(of: state),
            isUnavailable: state?.isUnavailable ?? true,
            onPower: { send(LightControl.power(light.entityId, on: $0)) },
            onBrightness: { send(LightControl.brightness(light.entityId, percent: Double($0))) },
            onOpen: open
        )
        .accessibilityIdentifier("customLights.light.\(light.entityId)")
    }

    private func send(_ command: LightControl.Command) {
        Task { try? await caller.callService(command.domain, command.service, data: command.serviceData) }
    }
}

extension Color {
    /// A Home Assistant `rgb_color`.
    init(rgb: CustomLightsConfig.RGB) {
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}
