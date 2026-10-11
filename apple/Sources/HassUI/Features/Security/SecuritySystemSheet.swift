import HassCore
import HassDesign
import SwiftUI

/// The security system sheet (web `SecurityControls.tsx` in the `#security-system` modal): the four alarm modes.
///
/// Disarming asks first, since it opens the house (HIG: Alerts). Tapping the current mode does nothing.
struct SecuritySystemSheet: View {
    var caller: any HassServiceCalling
    @Environment(EntityStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDisarm = false
    @ScaledMetric(relativeTo: .subheadline) private var minModeWidth: CGFloat = 130

    var body: some View {
        let state = store.entity(SecurityConfig.alarmEntityId).state
        let unavailable = state?.isUnavailable ?? true
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.m) {
                    Text(ScreenshotPrivacy.isRedacting ? "Hidden" : (unavailable ? "Unavailable" : SecurityConfig.stateText(state?.state)))
                        .font(.headline)
                        .foregroundStyle(HassTokens.Ink.secondary)
                        .accessibilityLabel("Current mode: \(ScreenshotPrivacy.isRedacting ? "Hidden" : SecurityConfig.stateText(state?.state))")
                        .accessibilityIdentifier("security.system.state")
                    Text("Mode")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    DynamicGridLayout(minCellWidth: minModeWidth, maxColumns: 4) {
                        ForEach(SecurityConfig.alarmModes) { mode in
                            AlarmModeButton(
                                mode: mode,
                                isSelected: !ScreenshotPrivacy.isRedacting && state?.state == mode.state,
                                isUnavailable: unavailable
                            ) {
                                select(mode, current: state?.state)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Security System")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Disarm the security system?", isPresented: $confirmingDisarm) {
                Button("Disarm", role: .destructive) { send(SecurityConfig.disarmMode) }
                    .accessibilityIdentifier("security.disarm.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Doors and motion stop triggering the alarm.")
            }
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
        Task { try? await caller.call(mode.call) }
    }
}

/// One alarm mode: icon and title, filled with the mode's color while selected (web `SecurityCard`).
struct AlarmModeButton: View {
    var mode: SecurityConfig.AlarmMode
    var isSelected: Bool
    var isUnavailable: Bool
    var action: () -> Void

    var body: some View {
        let tint = SecurityConfig.alarmTint(for: mode.state)
        Button(action: action) {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                Image(systemName: SymbolMap.symbol(for: mode.icon))
                    .font(.title2)
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? tint : .secondary)
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
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
            }
            .opacity(isUnavailable ? 0.5 : 1)
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
