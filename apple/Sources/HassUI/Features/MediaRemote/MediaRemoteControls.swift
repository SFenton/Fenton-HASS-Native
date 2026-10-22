import HassCore
import HassDesign
import SwiftUI

// MARK: - Shared pieces

/// Colors and sizes local to the remote.
enum RemoteStyle {
    /// Fill behind round buttons; sits on the sheet background, not on a material, so it keeps its edge.
    /// The remote's own round buttons use ``RoundButtonStyle``'s G cell grey; this stays for other sheets' capsules.
    static let buttonFill = Color.primary.opacity(0.09)
    /// Media device tint (web `media` tile tone), kept for room tiles; remote rows use ``ColorFamily/media``.
    static let media = Color(red: 0.36, green: 0.42, blue: 0.95)
    /// Power icon while the device is on (direction G red, web `red`).
    static let powerOn = HassTokens.Ink.danger
    /// Power icon while the device is off (web `green`): system green on dark, a deeper green on a light sheet (system
    /// green is 2.3:1 on white).
    static let powerOff = HassTokens.Ink.success

    /// The SF Symbol for a button's MDI icon.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }
}

/// A section title (web `SectionHeader`), exposed as a heading.
struct RemoteSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(HassTokens.Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A round icon button: tinted fill, pressed scale, dimmed while disabled (HIG: Buttons; ≥ 44 pt). Direction G draws
/// the remote's keys as grey circles in the sheet's cell colour (`.agents/design/direction-g.md`, Controls: Remote).
struct RoundButtonStyle: ButtonStyle {
    var diameter: CGFloat
    var fill: Color = HassTokens.Surface.sheetCell

    func makeBody(configuration: Configuration) -> some View {
        RoundButtonBody(configuration: configuration, diameter: diameter, fill: fill)
    }

    private struct RoundButtonBody: View {
        var configuration: Configuration
        var diameter: CGFloat
        var fill: Color
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // Pressed shrinks the key; with Reduce Motion it dims instead (opacity is allowed).
            configuration.label
                .frame(width: diameter, height: diameter)
                .background(fill, in: Circle())
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .opacity(isEnabled ? (configuration.isPressed && reduceMotion ? 0.7 : 1) : 0.4)
                .motionSafeAnimation(MotionTokens.quick, reduced: MotionTokens.quick, value: configuration.isPressed)
        }
    }
}

/// One configured remote button drawn as a round icon (web `RemoteButton`).
struct RemoteIconButton: View {
    var controller: MediaRemoteController
    var button: MediaRemoteButton
    var diameter: CGFloat
    var iconFont: Font = .title2
    /// The circle's fill; clear for keys drawn on a card (volume), which keep their 44 pt target.
    var fill: Color = HassTokens.Surface.sheetCell
    var onTextPrompt: (String) -> Void = { _ in }
    var onPress: () -> Void = {}

    var body: some View {
        Button {
            onPress()
            if let target = controller.press(button) { onTextPrompt(target) }
        } label: {
            RemoteButtonIcon(button: button, tone: controller.iconTone(for: button), font: iconFont)
        }
        .buttonStyle(RoundButtonStyle(diameter: diameter, fill: fill))
        .accessibilityLabel(button.label)
        .modifier(SemanticsTraits(semantics: controller.semantics(for: button)))
        .accessibilityIdentifier("remote.button.\(button.label)")
    }
}

/// A button's icon with its rotation and color rule applied.
struct RemoteButtonIcon: View {
    var button: MediaRemoteButton
    var tone: IconTone?
    var font: Font

    var body: some View {
        if button.hasIcon {
            Image(systemName: RemoteStyle.symbol(button.icon))
                .font(button.icon == "mdi:circle" ? .footnote : font)
                .fontWeight(.semibold)
                .rotationEffect(.degrees(button.iconRotationDegrees))
                // The power key's on and off colours cross-fade (`.agents/design/motion-components.md`, `PowerButton`).
                .stateForeground("RemoteButtonIcon", color)
                .accessibilityHidden(true)
        } else {
            // The SHIELD select button is blank; keep a body so the button keeps its size.
            Color.clear
        }
    }

    private var color: Color {
        switch tone {
        case .active: RemoteStyle.powerOn
        case .inactive: RemoteStyle.powerOff
        case nil: HassTokens.Ink.primary
        }
    }
}

/// Adds the traits and value for ``ControlSemantics`` (web `aria-checked` / `aria-pressed`).
struct SemanticsTraits: ViewModifier {
    var semantics: ControlSemantics

    func body(content: Content) -> some View {
        switch semantics {
        case let .toggle(isOn):
            content.accessibilityAddTraits(.isToggle).accessibilityValue(isOn ? "On" : "Off")
        case let .selection(isSelected):
            content.accessibilityAddTraits(isSelected ? .isSelected : [])
        case .command, .state:
            content
        }
    }
}

// MARK: - Power

/// The always-visible power button: a round d-pad button in the cell right of Up, icon red while on and green
/// while off (web `PowerButton`). It sat in a pill above the pad; the corner cell gives that row back to the
/// content (owner, 2026-10-13) and matches the Apple TV Remote, which keeps power in the top corner.
struct PowerButton: View {
    var controller: MediaRemoteController
    var diameter: CGFloat
    var onPress: () -> Void = {}

    var body: some View {
        let button = controller.config.power
        Button {
            onPress()
            controller.press(button)
        } label: {
            RemoteButtonIcon(button: button, tone: controller.iconTone(for: button), font: .title)
        }
        .buttonStyle(RoundButtonStyle(diameter: diameter))
        // Label from the config ("Power"); the state is the value, and Voice Control also takes "Power On/Off".
        .accessibilityLabel(button.label)
        .accessibilityInputLabels([button.label, controller.powerTitle])
        .modifier(PowerSemantics(semantics: controller.semantics(for: button), isOff: controller.isControlOff))
        .accessibilityIdentifier("remote.power")
    }
}

/// A toggle power button reads On/Off as a switch; a command one still reads the device's state.
private struct PowerSemantics: ViewModifier {
    var semantics: ControlSemantics
    var isOff: Bool

    func body(content: Content) -> some View {
        if case .toggle = semantics {
            content.modifier(SemanticsTraits(semantics: semantics))
        } else {
            content.accessibilityValue(isOff ? "Off" : "On")
        }
    }
}

// MARK: - D-pad

/// The 3×3 remote grid (`.agents/design/direction-g.md`, Controls: Remote): Back, Up and Power; Left, Select and
/// Right; Home, Down and the keyboard, as large grey circles with a light haptic on each press (web `RemoteGrid`
/// plus its navigation row; HIG: Playing haptics). Select is blank on a SHIELD and a dot on Apple TV. A remote
/// without a keyboard (Apple TV) leaves that corner empty.
struct DirectionalPad: View {
    var controller: MediaRemoteController
    /// The width the pad must fit (the leading column in two columns); `nil` for no limit.
    var maxWidth: CGFloat?
    /// Whether the inline keyboard is open (the keyboard key reads Expanded or Collapsed).
    var keyboardOpen = false
    /// The keyboard key asks for the text prompt on this entity.
    var onTextPrompt: (String) -> Void = { _ in }
    @ScaledMetric(relativeTo: .title) private var scaledDiameter: CGFloat = 76
    @State private var presses = 0

    /// 64–104 pt with Dynamic Type, but never wider than three buttons fit in `maxWidth` (never under 44 pt).
    private var diameter: CGFloat { Self.diameter(scaled: scaledDiameter, maxWidth: maxWidth) }

    static func diameter(scaled: CGFloat, maxWidth: CGFloat?) -> CGFloat {
        let size = min(max(scaled, 64), 104)
        guard let maxWidth else { return size }
        return max(HassTokens.minTarget, min(size, (maxWidth - 2 * HassTokens.Spacing.m) / 3))
    }

    var body: some View {
        let config = controller.config
        Grid(horizontalSpacing: HassTokens.Spacing.m, verticalSpacing: HassTokens.Spacing.m) {
            GridRow {
                button(config.back)
                button(config.up)
                // Power stays enabled while the directions are disabled: it is how the device turns on.
                PowerButton(controller: controller, diameter: diameter) { presses += 1 }
                    .accessibilitySortPriority(1) // Read first, as it was above the pad.
            }
            GridRow {
                button(config.left)
                button(config.select)
                button(config.right)
            }
            GridRow {
                button(config.home)
                button(config.down)
                if let keyboard = config.keyboard, !controller.hidesKeyboard {
                    button(keyboard)
                        .modifier(KeyboardState(isKeyboard: true, isOpen: keyboardOpen))
                } else {
                    gap
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(config.title) remote controls")
        .accessibilityIdentifier("remote.dpad")
    }

    private var gap: some View {
        Color.clear.frame(width: diameter, height: diameter).accessibilityHidden(true)
    }

    private func button(_ button: MediaRemoteButton) -> some View {
        RemoteIconButton(controller: controller, button: button, diameter: diameter, iconFont: .title,
                         onTextPrompt: onTextPrompt, onPress: { presses += 1 })
            .disabled(controller.controlsDisabled)
    }
}

// MARK: - Slider and keyboard state

/// A slider that commits on release, or at once for steps that arrive without a drag (VoiceOver adjust,
/// keyboard), so a drag doesn't send a service call per point (the web sends one per `input` event).
struct SliderDraft: Equatable {
    /// The value under the finger while dragging.
    var draft: Double?

    /// The value to draw.
    func shown(live: Double) -> Double { draft ?? live }

    /// A new value from the slider.
    mutating func set(_ value: Double, commit: (Double) -> Void) {
        if draft == nil { commit(value) } else { draft = value }
    }

    /// Drag start keeps the live value as the draft; drag end commits the draft.
    mutating func editingChanged(_ editing: Bool, live: Double, commit: (Double) -> Void) {
        if editing {
            draft = live
        } else if let value = draft {
            draft = nil
            commit(value)
        }
    }
}

/// The inline keyboard under the pad (web `TextPromptForm`).
struct KeyboardPrompt: Equatable {
    /// The entity typed into while open.
    var target: String?
    var text = ""

    var isOpen: Bool { target != nil }
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The keyboard button: opens for `target`, or closes when already open for it.
    mutating func toggle(_ target: String) {
        if self.target == target { close() } else { self.target = target }
    }

    /// Cancel: closes and clears the text.
    mutating func close() { self = KeyboardPrompt() }

    /// Send: types the text and closes; blank text sends nothing and stays open.
    @MainActor mutating func submit(with controller: MediaRemoteController) {
        guard let target, !isBlank else { return }
        controller.sendText(text, to: target)
        close()
    }
}

// MARK: - Controls tab

/// The Remote section under the pad: the inline keyboard while open, the volume card and the transport keys (web
/// `MediaRemoteModalTabContent`, controls tab; direction G: volume is a slider between speaker − and +).
struct RemoteControlsTab: View {
    var controller: MediaRemoteController
    /// Shared with the pad's keyboard key, which opens it.
    @Binding var keyboard: KeyboardPrompt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var volume = SliderDraft()
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var scaledDiameter: CGFloat = 56

    init(controller: MediaRemoteController, keyboard: Binding<KeyboardPrompt>) {
        self.controller = controller
        _keyboard = keyboard
    }

    private var diameter: CGFloat { min(max(scaledDiameter, HassTokens.minTarget), 88) }

    var body: some View {
        let config = controller.config
        VStack(alignment: .leading, spacing: HassTokens.Spacing.xl) {
            if keyboard.isOpen { keyboardForm }
            if controller.showsVolume {
                volumeCard
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(config.volumeTitle)
                    .accessibilityIdentifier("remote.section.volume")
            }
            row([config.pause, nil, config.play], disabled: controller.controlsDisabled)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Playback")
        }
        .motionSafeAnimation(.default, value: keyboard.isOpen)
        .onChange(of: keyboard.isOpen) { _, open in fieldFocused = open }
        // Opened from the pad while another section showed (two columns): focus once the field is here.
        .onAppear { if keyboard.isOpen { fieldFocused = true } }
    }

    /// Three equal columns; a `nil` slot keeps its space (web `ButtonRow` spacer).
    private func row(_ buttons: [MediaRemoteButton?], disabled: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                Group {
                    if let button {
                        RemoteIconButton(controller: controller, button: button, diameter: diameter)
                    } else {
                        Color.clear.frame(width: diameter, height: diameter).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(disabled)
    }

    // MARK: Volume

    /// The speaker's card: its name and level, mute, and the slider between Volume Down and Volume Up.
    private var volumeCard: some View {
        let config = controller.config
        let disabled = controller.volumeDisabled
        return VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack(alignment: .center, spacing: HassTokens.Spacing.m) {
                Text(config.volumeTitle)
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                Text("\(Int(volume.shown(live: Double(controller.volumePercent)).rounded()))%")
                    .font(.headline.weight(.regular))
                    .monospacedDigit()
                    .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                    .accessibilityHidden(true)
                RemoteIconButton(controller: controller, button: config.volumeMute, diameter: HassTokens.minTarget,
                                 iconFont: .body, fill: .clear)
                    .disabled(disabled)
            }
            HStack(spacing: HassTokens.Spacing.xs) {
                RemoteIconButton(controller: controller, button: config.volumeDown, diameter: HassTokens.minTarget,
                                 iconFont: .body, fill: .clear)
                volumeSlider
                RemoteIconButton(controller: controller, button: config.volumeUp, diameter: HassTokens.minTarget,
                                 iconFont: .body, fill: .clear)
            }
            .disabled(disabled)
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.m)
        .background(HassTokens.Surface.sheetCell, in: RoundedRectangle(cornerRadius: HassTokens.Radius.module, style: .continuous))
    }

    private var volumeSlider: some View {
        let live = Double(controller.volumePercent)
        let shown = volume.shown(live: live)
        let commit: (Double) -> Void = { controller.setVolume(percent: Int($0.rounded())) }
        return Slider(value: Binding(get: { volume.shown(live: live) }, set: { volume.set($0, commit: commit) }), in: 0...100, step: 1) {
            volume.editingChanged($0, live: live, commit: commit)
        }
        .tint(HassTokens.Ink.action)
        .disabled(controller.volumeDisabled)
        .frame(minHeight: HassTokens.minTarget)
        .accessibilityLabel("\(controller.config.volumeTitle) volume")
        .accessibilityValue("\(Int(shown.rounded())) percent")
        .accessibilityIdentifier("remote.volume")
    }

    // MARK: Keyboard

    private var field: some View {
        TextField("Enter text", text: $keyboard.text)
            .textFieldStyle(.roundedBorder)
            .remoteTextEntry()
            .focused($fieldFocused)
            .submitLabel(.send)
            .onSubmit { keyboard.submit(with: controller) }
            .frame(minHeight: HassTokens.minTarget)
            .accessibilityLabel("Text to send")
            .accessibilityIdentifier("remote.keyboard.field")
    }

    private var keyboardButtons: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Button("Send") { keyboard.submit(with: controller) }
                .buttonStyle(.borderedProminent)
                .disabled(keyboard.isBlank)
                .accessibilityIdentifier("remote.keyboard.send")
            Button("Cancel") { keyboard.close() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("remote.keyboard.cancel")
        }
        .controlSize(.large)
        .fixedSize()
    }

    private var keyboardForm: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text("Text to send")
                .font(.subheadline)
                .foregroundStyle(HassTokens.Surface.secondaryInSheet)
                .accessibilityHidden(true)
            // Field, Send and Cancel on one row like the web, so keyboard avoidance that keeps the focused field
            // visible keeps the buttons visible too; stacked at accessibility sizes. One layout only: a
            // `ViewThatFits` keeps the unused variant's elements in the accessibility tree.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: HassTokens.Spacing.s))
                : AnyLayout(HStackLayout(spacing: HassTokens.Spacing.s))
            layout {
                field
                keyboardButtons
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}

/// Tells VoiceOver whether the keyboard button's text field is open.
private struct KeyboardState: ViewModifier {
    var isKeyboard: Bool
    var isOpen: Bool

    func body(content: Content) -> some View {
        if isKeyboard {
            content.accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        } else {
            content
        }
    }
}

private extension View {
    /// Free text for a TV: no autocapitalization or autocorrection (web `autoCapitalize="none"`).
    func remoteTextEntry() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
}
