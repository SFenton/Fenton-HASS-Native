import HassCore
import HassDesign
import SwiftUI

/// The security system sheet (web `SecurityControls.tsx` in the `#security-system` modal): the four alarm modes.
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

/// The current mode and the mode grid (web `SecurityControls`), titled for a navigation stack. Shared by the
/// Security sheet and the Security System detail in Quick Links.
struct SecurityControls: View {
    var caller: any HassServiceCalling
    @Environment(EntityStore.self) private var store
    @State private var confirmingDisarm = false
    /// The tapped mode, shown until Home Assistant reports a change (rolled back if the call fails); created on the
    /// first tap (`.agents/patterns/optimistic-actions.md`).
    @State private var actions: OptimisticActions?
    @ScaledMetric(relativeTo: .subheadline) private var minModeWidth: CGFloat = 130

    var body: some View {
        let live = store.entity(SecurityConfig.alarmEntityId).state
        let shown = actions?.shown(SecurityConfig.alarmEntityId) ?? live?.state
        let unavailable = live?.isUnavailable ?? true
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                // Label and value instead of a longer replacement label: the clipping audit measures the
                // label against the drawn text's frame.
                Text(ScreenshotPrivacy.isRedacting ? "Hidden" : (unavailable ? "Unavailable" : SecurityConfig.stateText(shown)))
                    .font(.headline)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Current mode")
                    .accessibilityValue(ScreenshotPrivacy.isRedacting ? "Hidden" : (unavailable ? "Unavailable" : SecurityConfig.stateText(shown)))
                    .accessibilityIdentifier("security.system.state")
                Text("Mode")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                DynamicGridLayout(minCellWidth: minModeWidth, maxColumns: 4) {
                    ForEach(SecurityConfig.alarmModes) { mode in
                        AlarmModeButton(
                            mode: mode,
                            isSelected: !ScreenshotPrivacy.isRedacting && shown == mode.state,
                            isUnavailable: unavailable
                        ) {
                            select(mode, current: shown)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Security System")
        .inlineNavigationTitle()
        .alert("Disarm the security system?", isPresented: $confirmingDisarm) {
            Button("Disarm", role: .destructive) { send(SecurityConfig.disarmMode) }
                .accessibilityIdentifier("security.disarm.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Doors and motion stop triggering the alarm.")
        }
    }

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

/// One alarm mode: icon and title, filled with the mode's color while selected (web `SecurityCard`).
struct AlarmModeButton: View {
    var mode: SecurityConfig.AlarmMode
    var isSelected: Bool
    var isUnavailable: Bool
    var action: () -> Void
    /// One icon height for every mode, so titles line up (the slashed shield is taller than the others).
    @ScaledMetric(relativeTo: .title2) private var iconHeight: CGFloat = 30

    var body: some View {
        let tint = SecurityConfig.alarmTint(for: mode.state)
        Button(action: action) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Image(systemName: SymbolMap.symbol(for: mode.icon))
                    .font(.title2)
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(height: iconHeight)
                    // Unavailable dims the glyph and stroke only; the title and ground keep full strength (``GlassTileFace``).
                    .opacity(isUnavailable ? 0.5 : 1)
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    // One-word titles can't wrap; "Disarmed" may tighten rather than clip in a narrow column.
                    .allowsTightening(true)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(HassTokens.Spacing.m)
            .background {
                let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                shape.fill(.regularMaterial)
                    .overlay { if isSelected { shape.fill(tint.opacity(0.18)) } }
                    .clipShape(shape)
            }
            .overlay {
                RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                    .strokeBorder(isSelected ? tint : .clear, lineWidth: 2)
                    .opacity(isUnavailable ? 0.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "" : "Sets the security system to \(mode.title)")
        .accessibilityIdentifier("security.mode.\(mode.state)")
    }
}
