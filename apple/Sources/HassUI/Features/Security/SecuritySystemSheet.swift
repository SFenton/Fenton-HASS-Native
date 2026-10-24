import HassCore
import HassDesign
import SwiftUI

/// The security system sheet (web `SecurityControls.tsx` in the `#security-system` modal): the alarm card.
///
/// Disarming asks first, since it opens the house (HIG: Alerts). Tapping the current mode does nothing.
struct SecuritySystemSheet: View {
    var caller: any HassServiceCalling
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SecurityControls(caller: caller)
                .modalChrome()
                .toolbar { SheetCloseItem { dismiss() } }
        }
    }
}

/// The alarm card in a scrolling page, titled for a navigation stack. Shared by the Security sheet and the Security
/// System detail in Quick Links.
struct SecurityControls: View {
    var caller: any HassServiceCalling

    var body: some View {
        ScrollView {
            AlarmPanel(caller: caller)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .navigationTitle("Security System")
        .inlineNavigationTitle()
    }
}

// MARK: - Alarm card

/// The security system card (direction G mockup n3; web `SecurityControls`): a badge filled with the mode's colour,
/// the mode as a fact with when it began, and the four mode buttons. On the Security page it sits on a module, in a
/// sheet on the sheet's cell colour. A triggered alarm reddens the card.
///
/// Arming sends at once; Disarm asks first. The tapped mode shows until Home Assistant reports a change (rolled back
/// if the call fails; `.agents/patterns/optimistic-actions.md`).
struct AlarmPanel: View {
    var caller: any HassServiceCalling
    @Environment(EntityStore.self) private var store
    @Environment(\.tileSurface) private var surface
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var confirmingDisarm = false
    @State private var actions: OptimisticActions?
    /// Four buttons across a phone; fewer columns as text grows.
    @ScaledMetric(relativeTo: .footnote) private var minModeWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 44

    var body: some View {
        let live = store.entity(SecurityConfig.alarmEntityId).state
        let shown = actions?.shown(SecurityConfig.alarmEntityId) ?? live?.state
        let unavailable = live?.isUnavailable ?? true
        let redacting = ScreenshotPrivacy.isRedacting
        let triggered = !redacting && shown == "triggered"
        VStack(alignment: .leading, spacing: HassTokens.Spacing.m + 2) {
            header(shown: shown, live: live, unavailable: unavailable, redacting: redacting, triggered: triggered)
            DynamicGridLayout(minCellWidth: minModeWidth, maxColumns: 4, spacing: HassTokens.Spacing.s, equalRowHeights: true) {
                ForEach(SecurityConfig.modeButtons) { mode in
                    AlarmModeButton(
                        mode: mode,
                        isSelected: !redacting && shown == mode.state,
                        isUnavailable: unavailable,
                        onAlarm: triggered
                    ) {
                        select(mode, current: shown)
                    }
                }
            }
        }
        .padding(.horizontal, HassTokens.Spacing.m)
        .padding(.top, HassTokens.Spacing.l)
        .padding(.bottom, HassTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ground(triggered: triggered) }
        .alert("Disarm the Security System?", isPresented: $confirmingDisarm) {
            Button("Disarm", role: .destructive) { send(SecurityConfig.disarmMode) }
                .accessibilityIdentifier("security.disarm.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Doors and motion stop triggering the alarm.")
        }
    }

    // MARK: Header

    private func header(shown: String?, live: EntityState?, unavailable: Bool, redacting: Bool, triggered: Bool) -> some View {
        let family = redacting || unavailable ? nil : ColorFamily.security(alarmState: shown)
        let title = redacting ? "Hidden" : (unavailable ? "Unavailable" : SecurityConfig.panelTitle(shown))
        let since = redacting || unavailable ? nil : live.flatMap { SecurityConfig.sinceText($0.lastChanged) }
        let subtitle = ["Security System", since].compactMap { $0 }.joined(separator: " · ")
        let symbol = SymbolMap.symbol(for: redacting ? "mdi:shield-outline" : SecurityConfig.alarmIcon(for: shown))
        return HStack(spacing: HassTokens.Spacing.m) {
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                // Unavailable dims the glyph only; the text keeps full strength (``GlassTileFace``).
                .opacity(unavailable ? 0.5 : 1)
                .frame(width: badgeSize, height: badgeSize)
                // Unknown or hidden: a fixed mid grey under the white glyph, on a dark module and a white cell alike.
                .background {
                    Circle().fill(family?.fill ?? Color(rgb: Self.neutralBadge))
                        .stateColorTransition("AlarmPanel", value: family)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    // White on a page, the label colour in a light sheet.
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .stateForeground("AlarmPanel", subtitleInk(triggered: triggered))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HassTokens.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Security System")
        .accessibilityValue(redacting ? "Hidden" : [title, since].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("security.system.state")
    }

    /// The badge fill when the panel's state is unknown or hidden: `#636366`, 6:1 under the white glyph.
    private static let neutralBadge: UInt32 = 0x636366

    /// The subtitle's ink: the sheet's secondary ink, a stronger one over a light sheet's red alarm wash (the faint
    /// red lowers the ground's luminance), or the module's on a page.
    private func subtitleInk(triggered: Bool) -> Color {
        guard surface == .sheet else { return HassTokens.Surface.secondaryOnModule }
        return triggered && scheme == .light ? HassTokens.Ink.secondary : HassTokens.Surface.secondaryInSheet
    }

    // MARK: Ground

    /// The page module (dense, washed with the triggered red while the alarm sounds) or the sheet's cell colour.
    @ViewBuilder
    private func ground(triggered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.module, style: .continuous)
        let alarm = ColorFamily.securityTriggered.fill ?? .red
        switch surface {
        case .sheet:
            shape.fill(HassTokens.Surface.sheetCell)
                // Fainter over a white cell, so the secondary ink on it keeps 4.5:1. The triggered colour holds steady: it
                // fades in and out (`MotionTokens.state`) and never pulses.
                .overlay {
                    shape.fill(alarm.opacity(triggered ? (scheme == .light ? 0.16 : 0.42) : 0))
                        .stateColorTransition("AlarmPanel", value: triggered)
                }
        case .page:
            Color.clear
                .module(triggered ? .dense : .thin)
                .overlay {
                    shape.fill(alarm.opacity(triggered ? (reduceTransparency ? 0.6 : 0.42) : 0))
                        .stateColorTransition("AlarmPanel", value: triggered)
                }
                .stateColorTransition("AlarmPanel", value: triggered)
        }
    }

    // MARK: Actions

    /// Sends the mode, asking first when it disarms.
    private func select(_ mode: SecurityConfig.AlarmMode, current: String?) {
        guard current != mode.state else { return }
        if mode.needsConfirmation {
            confirmingDisarm = true
        } else {
            send(mode)
        }
    }

    private func send(_ mode: SecurityConfig.AlarmMode) {
        let actions = actions ?? OptimisticActions(
            store: store, rules: [SecurityConfig.alarmEntityId: .liveChange], caller: caller)
        self.actions = actions
        // Live change clears it: the panel reports "arming" on the way, and the page should follow the truth.
        actions.perform(mode.call, showing: [OptimisticIntent(SecurityConfig.alarmEntityId, value: mode.state)])
    }
}

// MARK: - Mode button

/// One alarm mode: glyph over a short label, filled with the mode's colour family while selected (direction G
/// mockup n3; web `SecurityCard`). At least 64 pt tall, with equal heights across the row.
/// What decides an alarm mode button's ground: selected, or sitting on the sounding alarm's wash.
struct AlarmModeLook: Equatable {
    var isSelected: Bool
    var onAlarm: Bool
}

struct AlarmModeButton: View {
    var mode: SecurityConfig.AlarmMode
    var isSelected: Bool
    var isUnavailable: Bool
    /// The alarm is sounding: unselected buttons sit on the card's red wash, so they lighten instead.
    var onAlarm = false
    var action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HassTokens.Spacing.l, style: .continuous)
        Button(action: action) {
            VStack(spacing: HassTokens.Spacing.xs) {
                Image(systemName: Self.symbol(for: mode))
                    .font(.title3)
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(height: iconHeight)
                    // Unavailable dims the glyph only; the label keeps full strength (``GlassTileFace``).
                    .opacity(isUnavailable ? 0.5 : 1)
                Text(mode.buttonTitle)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // White on a selected mode's fill; the label colour on the unselected ground (page, or a sheet in either
            // appearance).
            .stateForeground("AlarmModeButton", isSelected ? Color.white : HassTokens.Ink.primary)
            .padding(.vertical, HassTokens.Spacing.s)
            .padding(.horizontal, HassTokens.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
            .background {
                Group {
                    if isSelected, let fill = ColorFamily.security(alarmState: mode.state)?.fill {
                        // A chosen mode is a filled tile: the same edge and sheen as the tiles (``TileFinish``).
                        shape.fill(fill).tintedGlassEdge(cornerRadius: HassTokens.Spacing.l)
                    } else if onAlarm {
                        shape.fill(HassTokens.Ink.primary.opacity(0.14))
                    } else {
                        shape.fill(.fill.tertiary)
                    }
                }
                .stateColorTransition("AlarmModeButton", value: AlarmModeLook(isSelected: isSelected, onAlarm: onAlarm))
            }
            .contentShape(shape)
        }
        .buttonStyle(ModePressStyle())
        .disabled(isUnavailable)
        // Label and traits on the Button itself, so its identifier and disabled state stay on one element
        // (see `GlassTile`).
        .accessibilityLabel(mode.buttonTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "" : (mode.needsConfirmation ? "Disarms the security system" : "Sets the security system to \(mode.title)"))
        .accessibilityIdentifier("security.mode.\(mode.state)")
    }
}

extension AlarmModeButton {
    /// The button's glyph (mockup n3): what each mode means for the people inside, where the card's badge keeps the
    /// web's shield for the panel.
    static func symbol(for mode: SecurityConfig.AlarmMode) -> String {
        switch mode.state {
        case "armed_home": "house"
        case "armed_away": "figure.walk"
        case "armed_night": "moon"
        case "disarmed": "shield.slash"
        default: SymbolMap.symbol(for: mode.icon)
        }
    }
}

/// Dims while pressed and never fades a disabled label, which keeps 4.5:1 (as `GlassTileButtonStyle` does for tiles).
private struct ModePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
