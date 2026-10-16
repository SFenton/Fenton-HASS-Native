import HassCore
import HassDesign
import SwiftUI

/// A page's status chips (pattern: `.agents/patterns/status-rail.md`): Home shows all of them, Security its two.
/// They scroll in compact width and wrap in regular width, stopping short of a hinge (``ChipRail``).
struct StatusRail: View {
    /// The chips, in order.
    var chips: [HomeConfig.StatusChip] = HomeConfig.statusChips
    /// Accessibility identifier prefix: `<prefix>.chip.<sheet>`.
    var idPrefix = "home"
    var onOpen: (HomeConfig.ChipSheet) -> Void

    var body: some View {
        ChipRail {
            ForEach(chips) { chip in
                StatusChipView(chip: chip, idPrefix: idPrefix) { onOpen(chip.sheet) }
            }
        }
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
        let appearance = StatusChipAppearance.home(chip) { store.entity($0).state }
        StatusChipButton(title: chip.title, summary: summary, symbol: appearance.symbol,
                         family: appearance.family, isActive: appearance.isFilled, tint: appearance.tint, action: action)
        .accessibilityIdentifier("\(idPrefix).chip.\(chip.sheet.rawValue)")
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
    /// A computed look (a temperature or AQI colour, a contact state) that wins over ``family``; the chip draws filled.
    var tint: ChipTint? = nil
    /// `nil` draws an inert chip (no sheet), which is not a button.
    var action: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        let fill = StatusChipStyle.fillTint(family, isActive: isActive, tint: tint)
        return HStack(spacing: HassTokens.Spacing.s) {
            Image(systemName: symbol)
                .symbolVariant(fill != nil ? .fill : .none)
                .font(.body.weight(.semibold))
                // Colour only: the chip's width and glyph swap never ride this animation.
                .animation(StatusChipStyle.colorAnimation(reduceMotion: reduceMotion)) {
                    $0.foregroundStyle(fill?.glyphColor ?? HassTokens.Surface.secondaryOnModule)
                }
            VStack(alignment: .leading, spacing: 0) {
                // Fixed inks: the chip's ground is always dark (a family fill or the module), whatever the scheme.
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                // Full white on a fill: the 12% top highlight lifts the ground, and white at 92% measured 4.3:1 on the
                // armed-home and cooking chips when the summary wrapped into it (folded Duo, 2026-10-14).
                Text(summary).font(.caption)
                    .foregroundStyle(fill != nil ? Color.white : HassTokens.Surface.secondaryOnModule)
                    .monospacedDigit()
            }
        }
        .padding(.leading, HassTokens.Spacing.m)
        .padding(.trailing, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.xs)
        .frame(minHeight: StatusChipStyle.minHeight)
        .background { StatusChipBackground(tint: fill) }
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

    /// The tint the chip draws: a computed `tint`, else its active family's, else nil for the neutral chip.
    static func fillTint(_ family: ColorFamily?, isActive: Bool, tint: ChipTint?) -> ChipTint? {
        tint ?? fillFamily(family, isActive: isActive).flatMap { ChipTint(family: $0) }
    }

    /// The colour cross-fade (HIG, Motion: quick and subtle). Reduce Motion keeps a shorter fade: a colour change moves
    /// nothing, so it is the allowed substitute (`.agents/testing/apple/accessibility.md`, Reduce Motion).
    static func colorAnimation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.2 : 0.6)
    }
}

/// The chip's ground: the tint's fill with a slight top highlight, or the thin module when neutral. A colour change
/// cross-fades inside the fill only, so the capsule's size (a longer state text) never slides.
private struct StatusChipBackground: View {
    var tint: ChipTint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let tint {
                Color.clear
                    .animation(StatusChipStyle.colorAnimation(reduceMotion: reduceMotion)) { $0.background(tint.fillColor) }
                    .overlay { LinearGradient(colors: [.white.opacity(ChipTint.highlight), .clear], startPoint: .top, endPoint: .center) }
                    .clipShape(Capsule())
                    .transition(.opacity)
            } else {
                Color.clear.module(.thin, cornerRadius: StatusChipStyle.minHeight / 2)
                    .transition(.opacity)
            }
        }
        .animation(StatusChipStyle.colorAnimation(reduceMotion: reduceMotion), value: tint != nil)
    }
}
