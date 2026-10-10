import HassCore
import HassDesign
import SwiftUI

/// The Home status chips (pattern: `.agents/patterns/status-rail.md`).
struct StatusRail: View {
    var onOpen: (HomeConfig.ChipSheet) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HassTokens.Spacing.s) {
                ForEach(HomeConfig.statusChips) { chip in
                    StatusChipView(chip: chip) { onOpen(chip.sheet) }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
        }
    }
}

/// One chip. Observes only the entities its summary depends on.
struct StatusChipView: View {
    var chip: HomeConfig.StatusChip
    var action: () -> Void
    @Environment(EntityStore.self) private var store

    var body: some View {
        let summary = HomeConfig.summary(for: chip) { store.entity($0).state }
        let active = store.entity(chip.entityId).state?.isActive ?? false
        Button(action: action) {
            HStack(spacing: HassTokens.Spacing.s) {
                Image(systemName: SymbolMap.symbol(for: chip.icon))
                    .symbolVariant(active ? .fill : .none)
                    .foregroundStyle(active ? tint : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(chip.title).font(.subheadline.weight(.semibold))
                    // Primary: secondary caption text failed the contrast audit on the chip's material.
                    Text(summary).font(.caption).foregroundStyle(.primary).monospacedDigit()
                }
            }
            .padding(.horizontal, HassTokens.Spacing.m)
            .frame(minHeight: HassTokens.minTarget + 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.title), \(summary)")
        .accessibilityHint("Opens \(chip.title)")
        .accessibilityIdentifier("home.chip.\(chip.sheet.rawValue)")
    }

    private var tint: Color {
        switch chip.tone {
        case .light: HassTokens.Tint.light
        case .security: HassTokens.Tint.security
        case .climate: HassTokens.Tint.climate
        case .presence: HassTokens.Tint.presence
        case .contact: HassTokens.Tint.contact
        }
    }
}
