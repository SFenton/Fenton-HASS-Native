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
        let state = store.entity(chip.entityId).state
        let family = Self.family(chip.tone, alarmState: state?.state)
        StatusChipButton(title: chip.title, summary: summary, symbol: SymbolMap.symbol(for: chip.icon),
                         family: family, isActive: Self.isFilled(chip.tone, family: family, isActive: state?.isActive ?? false),
                         action: action)
        .accessibilityIdentifier("\(idPrefix).chip.\(chip.sheet.rawValue)")
    }

    /// The chip's colour family; security follows the alarm mode.
    static func family(_ tone: HomeConfig.ChipTone, alarmState: String?) -> ColorFamily? {
        switch tone {
        case .light: .lights
        case .security: ColorFamily.security(alarmState: alarmState)
        case .climate: .climate
        case .presence: .occupancy
        case .contact: .contact
        case .air: .air
        }
    }

    /// Whether the chip draws filled. Security (by mode), Climate and Air Quality always do, as on the web; the
    /// others only while their entity is active (lights on, someone home, a door open).
    static func isFilled(_ tone: HomeConfig.ChipTone, family: ColorFamily?, isActive: Bool) -> Bool {
        switch tone {
        case .security: family != nil
        case .climate, .air: true
        case .light, .presence, .contact: isActive
        }
    }
}

/// The chip drawing and semantics shared by the Home rail and room rails (pattern: `.agents/patterns/status-rail.md`).
struct StatusChipButton: View {
    var title: String
    var summary: String
    var symbol: String
    /// The chip's colour family (direction G, "Status chips follow the web"); nil draws it neutral.
    var family: ColorFamily?
    /// Whether the chip draws filled in its family colour, rather than neutral.
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
        let fill = StatusChipStyle.fillFamily(family, isActive: isActive)
        return HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: symbol)
                .symbolVariant(fill != nil ? .fill : .none)
                .font(.body.weight(.semibold))
                .foregroundStyle(fill?.chipGlyph ?? HassTokens.Ink.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HassTokens.Ink.primary)
                Text(summary).font(.caption)
                    .foregroundStyle(fill != nil ? Color.white.opacity(0.92) : HassTokens.Ink.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, HassTokens.Spacing.m)
        .padding(.trailing, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.xs)
        .frame(minHeight: StatusChipStyle.minHeight)
        .background { StatusChipStyle.background(fill) }
        .contentShape(Capsule())
    }
}

/// The chip's capsule (web `GlassTile` `.headerPill`: `border-radius: 999px`, 48 px tall; owner, 2026-10-13:
/// "Page-level chips are not pills like they are in web or the Apple Home app, and need background colors").
///
/// Direction G: an active chip fills with its family's chip colour and a slight top highlight; a neutral one sits
/// on the thin module, like the cards around it.
enum StatusChipStyle {
    /// Web `.headerPill` height (48 px), above the 44 pt minimum target.
    static let minHeight: CGFloat = 48

    /// The family whose fill the chip draws, or nil for the neutral chip.
    static func fillFamily(_ family: ColorFamily?, isActive: Bool) -> ColorFamily? {
        guard isActive, let family, family.chipFillRGB != nil else { return nil }
        return family
    }

    /// The chip's ground: the family's chip fill, or the thin module when neutral.
    @MainActor @ViewBuilder
    static func background(_ fill: ColorFamily?) -> some View {
        if let color = fill?.chipFill {
            Capsule()
                .fill(color)
                .overlay { Capsule().fill(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center)) }
        } else {
            Color.clear.module(.thin, cornerRadius: minHeight / 2)
        }
    }
}
