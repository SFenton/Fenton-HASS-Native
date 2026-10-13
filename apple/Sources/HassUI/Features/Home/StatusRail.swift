import HassCore
import HassDesign
import SwiftUI

/// A page's status chips (pattern: `.agents/patterns/status-rail.md`): Home shows all of them, Security its two.
struct StatusRail: View {
    /// The chips, in order.
    var chips: [HomeConfig.StatusChip] = HomeConfig.statusChips
    /// Accessibility identifier prefix: `<prefix>.chip.<sheet>`.
    var idPrefix = "home"
    var onOpen: (HomeConfig.ChipSheet) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HassTokens.Spacing.s) {
                ForEach(chips) { chip in
                    StatusChipView(chip: chip, idPrefix: idPrefix) { onOpen(chip.sheet) }
                }
            }
            .padding(.horizontal, HassTokens.Spacing.l)
        }
        // A horizontal scroll view draws into the side safe areas; clip it to its frame so chips never
        // scroll under the folded iPhone Duo's trailing toolbar rail.
        .clipped()
    }
}

/// One chip. Observes only the entities its summary depends on.
struct StatusChipView: View {
    var chip: HomeConfig.StatusChip
    var idPrefix = "home"
    var action: () -> Void
    @Environment(EntityStore.self) private var store

    var body: some View {
        let summary = ScreenshotPrivacy.isRedacting && [.security, .occupancy].contains(chip.sheet)
            ? "Hidden" : HomeConfig.summary(for: chip) { store.entity($0).state }
        let active = store.entity(chip.entityId).state?.isActive ?? false
        StatusChipButton(title: chip.title, summary: summary, symbol: SymbolMap.symbol(for: chip.icon), tint: tint,
                         isActive: active, action: action)
        .accessibilityIdentifier("\(idPrefix).chip.\(chip.sheet.rawValue)")
    }

    private var tint: Color {
        switch chip.tone {
        case .light: HassTokens.Tint.light
        case .security: HassTokens.Tint.security
        case .climate: HassTokens.Tint.climate
        case .presence: HassTokens.Tint.presence
        case .contact: HassTokens.Tint.contact
        case .air: RoomTone.air.color
        }
    }
}

/// The chip drawing and semantics shared by the Home rail and room rails (pattern: `.agents/patterns/status-rail.md`).
struct StatusChipButton: View {
    var title: String
    var summary: String
    var symbol: String
    var tint: Color
    var isActive: Bool
    /// `nil` draws an inert chip (no sheet), which is not a button.
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { face }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(summary)")
                .accessibilityHint("Opens \(title)")
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(summary)")
        }
    }

    private var face: some View {
        HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: symbol)
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(isActive ? tint : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                Text(summary).font(.caption).foregroundStyle(HassTokens.Ink.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, HassTokens.Spacing.m)
        .frame(minHeight: HassTokens.minTarget + 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous))
    }
}
