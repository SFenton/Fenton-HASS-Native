import HassCore
import HassDesign
import SwiftUI

// MARK: - Apps

/// App launch tiles: square artwork from the server, an icon fallback, and a ring on the running app
/// (web `AppButton`).
struct RemoteAppsTab: View {
    var controller: MediaRemoteController
    var imageServer: HassServer?
    @ScaledMetric(relativeTo: .subheadline) private var minTileWidth: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
            RoomSectionHeader(title: controller.config.appSectionTitle, inSheet: true)
            DynamicGridLayout(minCellWidth: minTileWidth, maxColumns: 4, equalRowHeights: true) {
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

/// One app tile (direction G, n4 remote apps and room Quick App Launch): the artwork on a rounded square, the app's
/// name under it, and "Playing" with a media-pink ring while it runs. Unavailable dims only the artwork, so the
/// name keeps its contrast.
struct AppTile: View {
    var app: MediaRemoteApp
    var display: MediaRemoteController.AppDisplay
    var imageURL: URL?
    var action: () -> Void
    @Environment(\.tileSurface) private var surface

    private let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: HassTokens.Spacing.xs) {
                ZStack {
                    ground
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
                    shape.strokeBorder(display.isActive ? ColorFamily.media.glyph : HassTokens.Surface.separator,
                                       lineWidth: display.isActive ? 3 : 1)
                }
                .opacity(display.isUnavailable ? 0.4 : 1)
                Text(app.title)
                    .font(.subheadline)
                    // White on a room page's module; the label colour in the remote sheet, in either appearance.
                    .foregroundStyle(surface == .sheet ? HassTokens.Ink.primary : HassTokens.Ink.onDark)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if display.isActive {
                    Text("Playing")
                        .font(.footnote)
                        .foregroundStyle(secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(display.isUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.title)
        .accessibilityAddTraits(.isButton)
        .modifier(SemanticsTraits(semantics: display.semantics))
        .accessibilityIdentifier("remote.app.\(app.title)")
    }

    /// The square behind the artwork: the sheet's cell colour in the remote, the module on a room page.
    @ViewBuilder
    private var ground: some View {
        if app.whiteBackground {
            Color.white
        } else if surface == .sheet {
            HassTokens.Surface.sheetCell
        } else {
            // The module material, opaque with Reduce Transparency; the tile's own shape clips it.
            Color.clear.module(cornerRadius: 0)
        }
    }

    private var secondaryInk: Color {
        surface == .sheet ? HassTokens.Surface.secondaryInSheet : HassTokens.Surface.secondaryOnModule
    }

    private var fallback: some View {
        Image(systemName: SymbolMap.symbol(for: app.icon ?? "mdi:play-box"))
            .font(.largeTitle)
            .foregroundStyle(app.whiteBackground ? Color.black : display.isActive ? ColorFamily.media.glyph : ColorFamily.media.offGlyph)
            .accessibilityHidden(true)
    }
}

// MARK: - Devices

/// The remote's devices as an inset grouped list (direction G: switches only in list rows; one option of several
/// is a checkmark row). Toggles and toggling commands are switches, a source choice is a checkmark row, and a
/// device that only reports a state is a plain row (web `DeviceButton` in a `DynamicGrid`).
struct RemoteDevicesTab: View {
    var controller: MediaRemoteController

    var body: some View {
        List {
            Section {
                ForEach(controller.config.devices) { device in
                    RemoteDeviceRow(device: device, display: controller.display(device)) { controller.tap(device) }
                }
            } header: {
                FormHeader("Devices")
            }
        }
    }
}

/// One device row: its glyph in the media family colour while on, its name and state, and a switch, a checkmark
/// or nothing for its semantics.
struct RemoteDeviceRow: View {
    var device: MediaRemoteDevice
    var display: MediaRemoteController.DeviceDisplay
    var action: () -> Void

    var body: some View {
        Group {
            switch display.semantics {
            case let .toggle(isOn):
                toggle(isOn)
            case .command:
                // Every command device toggles its device (`media_player.toggle`, the PC's on/off pair).
                toggle(display.isActive)
            case let .selection(isSelected):
                Button(action: action) {
                    HStack(spacing: HassTokens.Spacing.m) {
                        label
                        Spacer(minLength: HassTokens.Spacing.s)
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HassTokens.Ink.action)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(device.title)
                .accessibilityValue(display.subtitle)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                // Outside the combined element, so VoiceOver and XCUITest read it as dimmed (see GlassTile).
                .disabled(display.isDisabled)
            case .state:
                label
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(device.title)
                    .accessibilityValue(display.subtitle)
            }
        }
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityIdentifier("remote.device.\(device.title)")
    }

    private func toggle(_ isOn: Bool) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) { label }
            .disabled(display.isDisabled)
    }

    private var label: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.title)
                    .foregroundStyle(HassTokens.Ink.primary)
                Text(display.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HassTokens.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: SymbolMap.symbol(for: device.icon))
                .foregroundStyle(display.isActive && !display.isUnavailable ? ColorFamily.media.glyph : ColorFamily.media.offGlyph)
                .accessibilityHidden(true)
        }
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

/// Sync Box power and light sync, sync mode, intensity and brightness, and HDMI input (web `HueSyncTab`), as an
/// inset grouped list (direction G, n4 remote Hue Sync): switches in rows, segmented controls for the short mode
/// and intensity choices, and a checkmark list for the inputs.
///
/// Departure from the web: tapping the selected sync mode again while not syncing no longer restarts syncing (a
/// segmented control does not report a tap on its selected segment). Light Sync starts it.
struct HueSyncTab: View {
    var controller: MediaRemoteController
    var hue: HueSyncConfig
    @State private var brightness = SliderDraft()
    @Environment(\.dynamicTypeSize) private var typeSize

    static let help = "Light Sync turns on the Sync Box and starts syncing. Choosing a mode does the same. Presence lighting pauses until syncing stops."

    var body: some View {
        List {
            Section {
                toggleRow("Sync Box Power", entityId: hue.powerEntityId, symbol: "power", offProjections: [hue.lightSyncEntityId])
                toggleRow("Light Sync", entityId: hue.lightSyncEntityId, symbol: "lightbulb.2", onProjections: [hue.powerEntityId])
            } header: {
                FormHeader("Power and Sync")
            } footer: {
                FormFooter(Self.help)
            }
            Section {
                let mode = controller.hueSelect(hue.syncModeEntityId)
                choice("Sync Mode", select: mode, options: MediaRemoteState.orderedSyncModes(mode.options),
                       identifier: "remote.hue.mode") { controller.selectSyncMode(hue, mode: $0) }
            } header: {
                FormHeader("Sync Mode")
            }
            Section {
                let intensity = controller.hueSelect(hue.intensityEntityId)
                choice("Intensity", select: intensity, options: intensity.options, identifier: "remote.hue.intensity") {
                    controller.selectHue(hue.intensityEntityId, option: $0)
                }
                brightnessField
            } header: {
                FormHeader("Intensity")
            }
            Section {
                ForEach(controller.hdmiInputs(hue)) { input in hdmiRow(input) }
            } header: {
                FormHeader("HDMI Input")
            }
        }
    }

    private func toggleRow(_ title: String, entityId: String, symbol: String,
                           offProjections: [String] = [], onProjections: [String] = []) -> some View {
        let toggle = controller.hueToggle(entityId)
        return Toggle(isOn: Binding(get: { toggle.isOn }, set: { _ in
            controller.toggleHue(entityId, offProjections: offProjections, onProjections: onProjections)
        })) {
            Label {
                Text(title).foregroundStyle(HassTokens.Ink.primary)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(toggle.isOn ? ColorFamily.lights.glyph : ColorFamily.lights.offGlyph)
                    .accessibilityHidden(true)
            }
        }
        .disabled(toggle.isUnavailable)
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityIdentifier("remote.hue.\(title)")
    }

    /// A short choice as a segmented control; "Unavailable" while the select reports no options.
    @ViewBuilder
    private func choice(_ title: String, select: MediaRemoteController.SelectDisplay, options: [String], identifier: String,
                        choose: @escaping (String) -> Void) -> some View {
        if options.isEmpty {
            Text("Unavailable")
                .foregroundStyle(HassTokens.Ink.secondary)
                .frame(minHeight: HassTokens.minTarget)
                .accessibilityLabel(title)
                .accessibilityValue("Unavailable")
                .accessibilityIdentifier(identifier)
        } else {
            let picker = Picker(title, selection: Binding(get: { select.selected }, set: { choose($0) })) {
                ForEach(options, id: \.self) { option in
                    Text(StateText.titleCase(option)).tag(option)
                }
            }
            // Segments can't grow with Dynamic Type: a menu naming the choice at accessibility sizes (as ModalTabBar).
            Group {
                if typeSize.isAccessibilitySize {
                    picker.pickerStyle(.menu).frame(maxWidth: .infinity, minHeight: HassTokens.minTarget, alignment: .leading)
                } else {
                    picker.pickerStyle(.segmented).labelsHidden().controlSize(.large)
                }
            }
            .disabled(select.isUnavailable)
            .accessibilityIdentifier(identifier)
        }
    }

    private func hdmiRow(_ input: MediaRemoteController.HdmiInputDisplay) -> some View {
        Button {
            controller.selectHue(hue.hdmiInputEntityId, option: input.option)
        } label: {
            HStack(spacing: HassTokens.Spacing.m) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(input.option).foregroundStyle(HassTokens.Ink.primary)
                        Text(input.subtitle).font(.subheadline).foregroundStyle(HassTokens.Ink.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: input.isDisconnected ? "tv.slash" : "tv")
                        .foregroundStyle(input.isSelected && !input.isDisconnected ? ColorFamily.media.glyph : ColorFamily.media.offGlyph)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: HassTokens.Spacing.s)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.action)
                    .opacity(input.isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(input.option)
        .accessibilityValue(input.subtitle)
        .accessibilityAddTraits(input.isSelected ? [.isButton, .isSelected] : .isButton)
        // Outside the combined element, so an unplugged port reads as dimmed (see GlassTile).
        .disabled(input.isDisabled)
        .accessibilityIdentifier("remote.hue.hdmi.\(input.option)")
    }

    private var brightnessField: some View {
        let display = controller.hueBrightness(hue.brightnessEntityId)
        let shown = brightness.shown(live: display.value)
        let valueText = display.unavailableText ?? MediaRemoteState.numberString(shown)
        let commit: (Double) -> Void = { controller.setHueBrightness(hue.brightnessEntityId, value: $0) }
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
            HStack {
                Text("Brightness")
                Spacer()
                Text(valueText).monospacedDigit().foregroundStyle(HassTokens.Ink.secondary)
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
