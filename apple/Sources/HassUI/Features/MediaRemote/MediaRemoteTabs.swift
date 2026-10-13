import HassCore
import HassDesign
import SwiftUI

// MARK: - Apps

/// App launch tiles: square artwork from the server, an icon fallback, and a ring on the running app
/// (web `AppButton`).
struct RemoteAppsTab: View {
    var controller: MediaRemoteController
    var imageServer: HassServer?
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RemoteSectionHeader(title: controller.config.appSectionTitle)
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                ForEach(controller.config.apps) { app in
                    AppTile(app: app, display: controller.display(app), imageURL: imageURL(app)) { controller.tap(app) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func imageURL(_ app: MediaRemoteApp) -> URL? {
        guard let imageServer, let path = app.imagePath else { return nil }
        return imageServer.url(path)
    }
}

/// One app tile.
struct AppTile: View {
    var app: MediaRemoteApp
    var display: MediaRemoteController.AppDisplay
    var imageURL: URL?
    var action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        Button(action: action) {
            ZStack {
                shape.fill(app.whiteBackground ? Color.white : RemoteStyle.buttonFill)
                if let imageURL {
                    CachedImage(url: imageURL) { fallback }
                } else {
                    fallback
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 168)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(display.isActive ? HassTokens.Ink.primary : Color.primary.opacity(0.14),
                                   lineWidth: display.isActive ? 3 : 1)
            }
            .contentShape(shape)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(display.isUnavailable)
        .opacity(display.isUnavailable ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.title)
        .accessibilityAddTraits(.isButton)
        .modifier(SemanticsTraits(semantics: display.semantics))
        .accessibilityIdentifier("remote.app.\(app.title)")
    }

    private var fallback: some View {
        VStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: SymbolMap.symbol(for: app.icon ?? "mdi:play-box"))
                .font(.largeTitle)
            Text(app.title)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(app.whiteBackground ? Color.black : HassTokens.Ink.primary)
        .padding(HassTokens.Spacing.s)
    }
}

// MARK: - Devices

/// Device tiles in the shared grid (web `DeviceButton` in a `DynamicGrid`, 2–4 columns).
struct RemoteDevicesTab: View {
    var controller: MediaRemoteController
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RemoteSectionHeader(title: "Devices")
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4) {
                ForEach(controller.config.devices) { device in
                    let display = controller.display(device)
                    RemoteGlassTile(
                        title: device.title,
                        subtitle: display.subtitle,
                        symbol: SymbolMap.symbol(for: device.icon),
                        tint: device.entityId.hasPrefix("input_boolean.") ? HassTokens.Tint.presence : RemoteStyle.media,
                        isActive: display.isActive && !display.isUnavailable,
                        isDisabled: display.isDisabled,
                        semantics: display.semantics
                    ) {
                        controller.tap(device)
                    }
                    .accessibilityIdentifier("remote.device.\(device.title)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// ``GlassTile`` with the remote's semantics: toggles read On/Off, choices are selected, read-only tiles aren't
/// buttons. (TODO(orchestrator): fold `.selection` and `.state` into `GlassTile.Kind`.)
struct RemoteGlassTile: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    var isActive: Bool
    var isDisabled: Bool
    var semantics: ControlSemantics
    var action: () -> Void

    var body: some View {
        // `.disabled` again outside: GlassTile's own sits inside its combined accessibility element, so
        // assistive technologies still reported unplugged HDMI ports as enabled.
        let tile = GlassTile(title: title, subtitle: subtitle, symbol: symbol, tint: tint, isActive: isActive,
                             isUnavailable: isDisabled, kind: kind, action: action)
            .disabled(isDisabled)
        switch semantics {
        case .state:
            tile.allowsHitTesting(false).accessibilityRemoveTraits(.isButton)
        case let .selection(isSelected):
            tile.accessibilityAddTraits(isSelected ? .isSelected : [])
        case .toggle, .command:
            tile
        }
    }

    private var kind: GlassTileKind {
        if case .toggle = semantics { return .toggle }
        return .command
    }
}

// MARK: - Hue Sync

/// Sync Box power and light sync, sync mode, intensity and brightness, and HDMI input (web `HueSyncTab`).
struct HueSyncTab: View {
    var controller: MediaRemoteController
    var hue: HueSyncConfig
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 140
    @ScaledMetric(relativeTo: .title2) private var scaledModeDiameter: CGFloat = 60
    @State private var brightness = SliderDraft()

    static let help = "Light sync turns on the Sync Box and starts entertainment syncing. Choosing a sync mode does the same in that mode. Presence lighting pauses, then resumes when syncing stops."

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            section("Power and Sync") {
                grid {
                    toggleTile("Sync Box Power", entityId: hue.powerEntityId, symbol: "power", tint: RemoteStyle.media,
                               offProjections: [hue.lightSyncEntityId])
                    toggleTile("Light Sync", entityId: hue.lightSyncEntityId, symbol: "lightbulb.2", tint: HassTokens.Tint.light,
                               onProjections: [hue.powerEntityId])
                }
                Text(Self.help)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("Sync Mode") { syncModes }
            section("Intensity") {
                let intensity = controller.hueSelect(hue.intensityEntityId)
                grid {
                    ForEach(intensity.options, id: \.self) { option in
                        RemoteGlassTile(title: StateText.titleCase(option), symbol: "gauge.with.dots.needle.50percent",
                                        tint: HassTokens.Tint.light, isActive: intensity.selected == option,
                                        isDisabled: intensity.isUnavailable, semantics: .selection(isSelected: intensity.selected == option)) {
                            controller.selectHue(hue.intensityEntityId, option: option)
                        }
                        .accessibilityIdentifier("remote.hue.intensity.\(option)")
                    }
                }
                brightnessField
            }
            section("HDMI Input") {
                grid {
                    ForEach(controller.hdmiInputs(hue)) { input in
                        RemoteGlassTile(title: input.option, subtitle: input.subtitle, symbol: input.isDisconnected ? "tv.slash" : "tv",
                                        tint: HassTokens.Tint.presence, isActive: input.isSelected && !input.isDisconnected,
                                        isDisabled: input.isDisabled, semantics: .selection(isSelected: input.isSelected)) {
                            controller.selectHue(hue.hdmiInputEntityId, option: input.option)
                        }
                        .accessibilityIdentifier("remote.hue.hdmi.\(input.option)")
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RemoteSectionHeader(title: title)
            content()
        }
        .accessibilityElement(children: .contain)
    }

    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 2) { content() }
    }

    private func toggleTile(_ title: String, entityId: String, symbol: String, tint: Color,
                            offProjections: [String] = [], onProjections: [String] = []) -> some View {
        let toggle = controller.hueToggle(entityId)
        return RemoteGlassTile(title: title, subtitle: toggle.subtitle, symbol: symbol, tint: tint, isActive: toggle.isOn,
                               isDisabled: toggle.isUnavailable, semantics: .toggle(isOn: toggle.isOn)) {
            controller.toggleHue(entityId, offProjections: offProjections, onProjections: onProjections)
        }
        .accessibilityIdentifier("remote.hue.\(title)")
    }

    private var syncModes: some View {
        let mode = controller.hueSelect(hue.syncModeEntityId)
        let diameter = min(max(scaledModeDiameter, HassTokens.minTarget), 96)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(MediaRemoteState.orderedSyncModes(mode.options), id: \.self) { option in
                let selected = mode.selected == option
                Button {
                    controller.selectSyncMode(hue, mode: option)
                } label: {
                    VStack(spacing: HassTokens.Spacing.s) {
                        Image(systemName: SymbolMap.symbol(for: MediaRemoteState.syncModeIcon(option)))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(selected ? Color.black : HassTokens.Ink.primary)
                            .frame(width: diameter, height: diameter)
                            .background(selected ? HassTokens.Tint.light : RemoteStyle.buttonFill, in: Circle())
                        Text(StateText.titleCase(option))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HassTokens.Ink.primary)
                            .multilineTextAlignment(.center)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(mode.isUnavailable)
                .opacity(mode.isUnavailable ? 0.4 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StateText.titleCase(option))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("remote.hue.mode.\(option)")
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sync Mode")
    }

    private var brightnessField: some View {
        let display = controller.hueBrightness(hue.brightnessEntityId)
        let shown = brightness.shown(live: display.value)
        let valueText = display.unavailableText ?? MediaRemoteState.numberString(shown)
        let commit: (Double) -> Void = { controller.setHueBrightness(hue.brightnessEntityId, value: $0) }
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            HStack {
                Text("Brightness").font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText).font(.subheadline).monospacedDigit()
            }
            .foregroundStyle(HassTokens.Ink.primary)
            .accessibilityHidden(true)
            Slider(value: Binding(get: { brightness.shown(live: display.value) }, set: { brightness.set($0, commit: commit) }),
                   in: display.range, step: display.step) {
                brightness.editingChanged($0, live: display.value, commit: commit)
            }
            .tint(HassTokens.Tint.light)
            .disabled(display.isUnavailable)
            .frame(minHeight: HassTokens.minTarget)
            .accessibilityLabel("Brightness")
            .accessibilityValue(valueText)
            .accessibilityIdentifier("remote.hue.brightness")
        }
    }
}
