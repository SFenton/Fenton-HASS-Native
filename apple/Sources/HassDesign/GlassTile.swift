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
        } else {
            Button(action: action) { face }
                .buttonStyle(.plain)
                .disabled(isUnavailable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityAddTraits(traits)
                // Outside the combined element too, so assistive technologies report the tile as dimmed.
                .disabled(isUnavailable)
        }
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
                .strokeBorder(isActive ? tint.opacity(0.5) : .clear, lineWidth: 1)
        }
        .opacity(isUnavailable ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
    }
}
