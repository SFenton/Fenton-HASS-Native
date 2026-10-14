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
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive ? tint : HassTokens.Ink.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                Text(summary).font(.caption).foregroundStyle(HassTokens.Ink.secondary).monospacedDigit()
            }
        }
        .padding(.leading, HassTokens.Spacing.m)
        .padding(.trailing, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.xs)
        .frame(minHeight: StatusChipStyle.minHeight)
        .background { StatusChipStyle.fill(tint: tint, isActive: isActive) }
        .contentShape(Capsule())
    }
}

/// The chip's pill shape and fill (web `GlassTile` `.headerPill`: `border-radius: 999px`, 48 px tall, a frosted
/// fill with a light top edge; owner, 2026-10-13: "Page-level chips are not pills like they are in web or the
/// Apple Home app, and need background colors").
enum StatusChipStyle {
    /// Web `.headerPill` height (48 px), above the 44 pt minimum target.
    static let minHeight: CGFloat = 48

    /// How strongly the chip's tone colors its fill: stronger while its entity is active.
    static func tintOpacity(isActive: Bool) -> Double { isActive ? 0.32 : 0.14 }

    /// A capsule of frosted material washed with the chip's tone, with the web's light top edge.
    @ViewBuilder
    static func fill(tint: Color, isActive: Bool) -> some View {
        Capsule()
            .fill(.regularMaterial)
            .overlay { Capsule().fill(tint.opacity(tintOpacity(isActive: isActive))) }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5) }
    }
}
