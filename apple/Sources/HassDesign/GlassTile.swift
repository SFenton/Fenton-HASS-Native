import SwiftUI

/// The shared entity tile (pattern: `.agents/patterns/entity-tile.md`).
///
/// Pure UI: callers pass values and an action, never a store.
public struct GlassTile: View {
    // MARK: - Inputs

    public var title: String
    public var subtitle: String?
    public var symbol: String
    public var tint: Color
    public var isActive: Bool
    public var isUnavailable: Bool
    /// Toggles get `.isToggle` semantics; navigation gets a chevron.
    public var kind: Kind
    public var action: () -> Void

    /// What tapping the tile does (web `ControlSemantics`).
    public enum Kind: Sendable { case toggle, navigate, command }

    /// Creates a tile.
    public init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color,
        isActive: Bool,
        isUnavailable: Bool = false,
        kind: Kind = .toggle,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.isActive = isActive
        self.isUnavailable = isUnavailable
        self.kind = kind
        self.action = action
    }

    // MARK: - Body

    public var body: some View {
        Button(action: action) {
            GlassTileFace(
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                tint: tint,
                isActive: isActive,
                isUnavailable: isUnavailable,
                showsChevron: kind == .navigate
            )
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        // `children: .ignore` replaces the Button's own element, so the role is restated here.
        .accessibilityAddTraits(kind == .toggle ? [.isButton, .isToggle] : .isButton)
    }

    private var accessibilityValue: String {
        if isUnavailable { return "Unavailable" }
        if kind == .toggle { return isActive ? "On" : "Off" }
        return subtitle ?? ""
    }
}

// MARK: - Face

/// The tile's drawing, shared by ``GlassTile`` and ``BrightnessTile`` so every entity tile looks the same.
struct GlassTileFace: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    var isActive: Bool
    var isUnavailable: Bool
    var showsChevron = false
    /// 0...1 fill drawn from the leading edge (brightness), or `nil` for none.
    var level: Double?
    /// The fill's color; defaults to ``tint``.
    var levelTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3)
                    .symbolVariant(isActive ? .fill : .none)
                    .foregroundStyle(isActive ? tint : .secondary)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HassTokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Ink.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Text wraps and the tile grows at large Dynamic Type instead of truncating.
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(HassTokens.Spacing.m)
        .background {
            let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
            shape.fill(.regularMaterial)
                .overlay(alignment: .leading) {
                    if let level, level > 0 {
                        GeometryReader { proxy in
                            // A light wash keeps the label text above 4.5:1 on any light color.
                            Rectangle()
                                .fill((levelTint ?? tint).opacity(0.32))
                                .frame(width: proxy.size.width * min(1, level))
                        }
                    }
                }
                .clipShape(shape)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
                .strokeBorder(isActive ? tint.opacity(0.5) : .clear, lineWidth: 1)
        }
        .opacity(isUnavailable ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
    }
}
