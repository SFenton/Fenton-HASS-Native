import SwiftUI

/// The shared entity tile (pattern: `.agents/patterns/entity-tile.md`).
///
/// Pure UI: callers pass values and an action, never a store. An optional trailing accessory (the bathroom fan's
/// lock and power buttons) sits in the tile's top-trailing corner as its own controls, outside the tile's button.
public struct GlassTile<Accessory: View>: View {
    // MARK: - Inputs

    public var title: String
    public var subtitle: String?
    public var symbol: String
    public var tint: Color
    public var isActive: Bool
    public var isUnavailable: Bool
    /// Toggles get `.isToggle` semantics; navigation gets a chevron; read-only tiles are not buttons.
    public var kind: Kind
    /// A state wash drawn under the material (towel rack on, an Eight Sleep side heating).
    public var wash: Color?
    /// 0...1 progress fill from the leading edge (dishwasher), or `nil` for none.
    public var progress: Double?
    /// The progress fill's color; defaults to ``tint``.
    public var progressTint: Color?
    /// Identifier for the tile's own control only (``tileIdentifier(_:)``).
    private var identifier: String?
    public var action: () -> Void
    private let accessory: Accessory

    /// What tapping the tile does.
    public typealias Kind = GlassTileKind

    @State private var accessoryWidth: CGFloat = 0

    /// Creates a tile with a trailing accessory.
    public init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color,
        isActive: Bool,
        isUnavailable: Bool = false,
        kind: Kind = .toggle,
        wash: Color? = nil,
        progress: Double? = nil,
        progressTint: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.isActive = isActive
        self.isUnavailable = isUnavailable
        self.kind = kind
        self.wash = wash
        self.progress = progress
        self.progressTint = progressTint
        self.action = action
        self.accessory = accessory()
    }

    // MARK: - Body

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            tile
            accessory
                .padding([.top, .trailing], HassTokens.Spacing.s)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { accessoryWidth = $0 }
        }
    }

    @ViewBuilder
    private var tile: some View {
        let face = GlassTileFace(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            tint: tint,
            isActive: isActive,
            isUnavailable: isUnavailable && kind != .state,
            showsChevron: kind == .navigate,
            level: progress,
            levelTint: progressTint,
            wash: wash,
            trailingInset: accessoryWidth
        )
        if kind == .state {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .modifier(TileIdentifier(identifier: identifier))
        } else {
            Button(action: action) { face }
                .buttonStyle(GlassTileButtonStyle())
                .disabled(isUnavailable)
                // Label and value go on the Button itself: wrapping it in `.accessibilityElement(children: .ignore)`
                // left the Button exposed beside a second element, so identifiers and disabled state split between them.
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityAddTraits(traits)
                // Outside the combined element too, so assistive technologies report the tile as dimmed.
                .disabled(isUnavailable)
                .modifier(TileIdentifier(identifier: identifier))
        }
    }

    /// Sets the accessibility identifier on the tile's control only. Use this, not `.accessibilityIdentifier`, on a
    /// tile with an accessory: an identifier on the whole tile also lands on the accessory's buttons and hides
    /// theirs (bathroom fan Lock and Power, 2026-10-12).
    public func tileIdentifier(_ identifier: String) -> GlassTile {
        var tile = self
        tile.identifier = identifier
        return tile
    }

    private var traits: AccessibilityTraits {
        switch kind {
        case .toggle: .isToggle
        case let .selection(isSelected): isSelected ? .isSelected : []
        default: []
        }
    }

    private var accessibilityValue: String {
        if isUnavailable { return "Unavailable" }
        if kind == .toggle { return isActive ? "On" : "Off" }
        return subtitle ?? ""
    }
}

// MARK: - Button style

/// Presses like `.plain` but never fades the label when disabled: a locked tile still carries its state
/// ("Away", "Select the user … first"), so its text must keep 4.5:1. ``GlassTileFace`` mutes only the icon
/// and border instead, and VoiceOver still reads the tile as dimmed.
struct GlassTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

public extension GlassTile where Accessory == EmptyView {
    /// Creates a tile.
    init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color,
        isActive: Bool,
        isUnavailable: Bool = false,
        kind: Kind = .toggle,
        wash: Color? = nil,
        progress: Double? = nil,
        progressTint: Color? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint, isActive: isActive,
                  isUnavailable: isUnavailable, kind: kind, wash: wash, progress: progress, progressTint: progressTint,
                  action: action) { EmptyView() }
    }
}

/// What tapping the tile does (web `ControlSemantics`).
public enum GlassTileKind: Equatable, Sendable {
    /// An on/off switch: `.isToggle`, value On/Off.
    case toggle
    /// Opens a page or sheet: chevron.
    case navigate
    /// Fires a command.
    case command
    /// One of a set of choices: `.isSelected` while chosen (web `aria-pressed`).
    case selection(isSelected: Bool)
    /// Shows a state only: not a button, never dimmed as disabled.
    case state
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
    /// A state wash over the material.
    var wash: Color?
    /// Room kept free at the trailing edge for an accessory.
    var trailingInset: CGFloat = 0

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack {
                // Decorative: the title names the tile. Symbols carry built-in labels ("Humidifier"), which the audit
                // then flagged as clipped text on iPad (glyph wider than its frame).
                Image(systemName: symbol)
                    .font(.title3)
                    .symbolVariant(isActive ? .fill : .none)
                    .foregroundStyle(isActive && isEnabled ? tint : .secondary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
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
        .padding(.trailing, trailingInset)
        // Text wraps and the tile grows at large Dynamic Type instead of truncating.
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(HassTokens.Spacing.m)
        .background {
            let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
            shape.fill(.regularMaterial)
                // A light wash, like the level fill, keeps label text above 4.5:1 on any state color.
                .overlay { if let wash { shape.fill(wash.opacity(0.6)) } }
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
                .strokeBorder(isActive ? tint.opacity(isEnabled ? 0.5 : 0.25) : .clear, lineWidth: 1)
        }
        .opacity(isUnavailable ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
    }
}

/// Applies an identifier only when one is set.
private struct TileIdentifier: ViewModifier {
    var identifier: String?

    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}
