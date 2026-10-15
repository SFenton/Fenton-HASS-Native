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
    /// The glyph and rim colour of a ``TileFaceStyle/tinted`` face; defaults to the family's glyph colour.
    public var tint: Color
    /// The device's colour family (direction G). Nil keeps the tinted face until the caller picks one.
    public var family: ColorFamily?
    public var isActive: Bool
    public var isUnavailable: Bool
    /// Draws the error face: a red glyph and red state ("Didn't Respond") on a dense ground.
    public var isError: Bool
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
        tint: Color? = nil,
        family: ColorFamily? = nil,
        isActive: Bool,
        isUnavailable: Bool = false,
        isError: Bool = false,
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
        self.tint = tint ?? family?.glyph ?? .accentColor
        self.family = family
        self.isActive = isActive
        self.isUnavailable = isUnavailable
        self.isError = isError
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
            family: family,
            isActive: isActive,
            isUnavailable: isUnavailable && kind != .state,
            isError: isError,
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
        if isError { return subtitle ?? "Error" }
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
        tint: Color? = nil,
        family: ColorFamily? = nil,
        isActive: Bool,
        isUnavailable: Bool = false,
        isError: Bool = false,
        kind: Kind = .toggle,
        wash: Color? = nil,
        progress: Double? = nil,
        progressTint: Color? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint, family: family, isActive: isActive,
                  isUnavailable: isUnavailable, isError: isError, kind: kind, wash: wash, progress: progress,
                  progressTint: progressTint, action: action) { EmptyView() }
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
/// Public for tiles whose container handles the tap, such as a `NavigationLink` label.
///
/// Direction G faces (``TileFaceStyle``): off is dark with the glyph in its family colour, a light that is on is
/// the warm lit tile, other devices fill with their family colour, and an error is a red glyph and state.
public struct GlassTileFace: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    var family: ColorFamily?
    var isActive: Bool
    var isUnavailable: Bool
    var isError = false
    var showsChevron = false
    /// 0...1 fill drawn from the leading edge (brightness, a cycle's progress), or `nil` for none.
    var level: Double?
    /// The level fill's colour on a tinted face, or a light's colour washed over the lit band.
    var levelTint: Color?
    /// A state wash over a dark face.
    var wash: Color?
    /// Room kept free at the trailing edge for an accessory.
    var trailingInset: CGFloat = 0

    /// Creates a tile face.
    public init(title: String, subtitle: String? = nil, symbol: String, tint: Color, family: ColorFamily? = nil,
                isActive: Bool, isUnavailable: Bool = false, isError: Bool = false, showsChevron: Bool = false,
                level: Double? = nil, levelTint: Color? = nil, wash: Color? = nil, trailingInset: CGFloat = 0) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.family = family
        self.isActive = isActive
        self.isUnavailable = isUnavailable
        self.isError = isError
        self.showsChevron = showsChevron
        self.level = level
        self.levelTint = levelTint
        self.wash = wash
        self.trailingInset = trailingInset
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.tileFillsHeight) private var fillsHeight
    @Environment(\.tileSurface) private var surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: TileFaceStyle {
        .resolve(family: family, isActive: isActive, isError: isError, isUnavailable: isUnavailable)
    }

    public var body: some View {
        let style = style
        let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            HStack {
                // Decorative: the title names the tile. Symbols carry built-in labels ("Humidifier"), which the audit
                // then flagged as clipped text on iPad (glyph wider than its frame).
                Image(systemName: symbol)
                    .font(.title3)
                    .symbolVariant(isActive ? .fill : .none)
                    .foregroundStyle(glyphColor(style))
                    // Unavailable dims the glyph and the tinted stroke only. The title and "Unavailable" keep 4.5:1
                    // and the ground stays full strength, so wallpaper never shows through behind white text: a
                    // whole-face fade left the text at 2.4:1 (signed-in Security tab before states arrived, 2026-10-14).
                    .opacity(isUnavailable ? 0.5 : 1)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(secondaryInk(style).opacity(0.8))
                        .accessibilityHidden(true)
                }
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryInk(style))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(secondaryInk(style))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.trailing, trailingInset)
        // Text wraps and the tile grows at large Dynamic Type instead of truncating. In an equal-height grid the face
        // also fills the row height it is offered.
        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .padding(HassTokens.Spacing.m)
        .background { ground(style).clipShape(shape) }
        .overlay {
            if style == .tinted {
                shape.strokeBorder(tint.opacity(isEnabled ? 0.5 : 0.25), lineWidth: 1)
                    .opacity(isUnavailable ? 0.5 : 1)
            }
        }
        .contentShape(shape)
    }

    // MARK: Ink

    // Every ground is fixed (dark module or sheet cell, lit tile, family fill), so the inks are fixed too and never
    // follow the colour scheme: a light-appearance gallery drew black titles on the dark ground (2.7:1).

    private func glyphColor(_ style: TileFaceStyle) -> Color {
        let muted = HassTokens.Surface.secondaryOnModule
        return switch style {
        case .off: isEnabled ? (family?.offGlyph ?? muted) : muted
        case .lit: LitTile.glyph
        case let .filled(family): family.ink
        case .tinted: isEnabled ? tint : muted
        case .error: Color(rgb: HassTokens.Palette.red)
        }
    }

    private func primaryInk(_ style: TileFaceStyle) -> Color {
        switch style {
        case .lit: LitTile.ink
        case let .filled(family): family.ink
        default: .white
        }
    }

    private func secondaryInk(_ style: TileFaceStyle) -> Color {
        switch style {
        case .lit: LitTile.secondaryInk
        case let .filled(family): family.secondaryInk
        case .error: Color(rgb: HassTokens.Palette.red)
        // A state wash lifts the dark ground toward its colour, and over a bright sky the 68% ink fell to 4.3:1
        // (folded Duo Quick Links: Armed Home and the food tile, 2026-10-14).
        default: wash != nil ? HassTokens.Surface.secondaryOnWash : HassTokens.Surface.secondaryOnModule
        }
    }

    // MARK: Ground

    @ViewBuilder
    private func ground(_ style: TileFaceStyle) -> some View {
        switch style {
        case .off, .tinted, .error:
            ZStack(alignment: .leading) {
                darkGround(dense: style == .error)
                if let wash { wash.opacity(0.6) }
                levelBand { (levelTint ?? tint).opacity(0.32) }
            }
        case .lit:
            ZStack(alignment: .leading) {
                LitTile.base
                levelBand(default: 1) {
                    LinearGradient(colors: [LitTile.bandTop, LitTile.bandBottom], startPoint: .top, endPoint: .bottom)
                        // A coloured bulb tints its band; the band stays light enough for dark ink.
                        .overlay { if let levelTint { levelTint.opacity(LitTile.bulbTint) } }
                }
            }
        case let .filled(family):
            ZStack(alignment: .leading) {
                if family == .power {
                    LinearGradient(colors: [LitTile.powerTop, family.fill ?? .yellow], startPoint: .top, endPoint: .bottom)
                } else {
                    (family.fill ?? .clear)
                    // The slight top highlight from the mockups.
                    LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                }
                // Progress is a lighter band from the leading edge (a vacuum's or dishwasher's cycle). With white
                // ink the part still to go is shaded instead, so text over either part keeps its contrast (a white
                // band measured 4.2:1 under the state on cleaning purple); with dark ink the band is lightened.
                if let level, level > 0 {
                    if family.spec.darkInk {
                        levelBand { Color.white.opacity(TileFaceStyle.progressLighten) }
                    } else {
                        GeometryReader { proxy in
                            Color.black.opacity(TileFaceStyle.progressShade)
                                .frame(width: proxy.size.width * (1 - min(1, level)))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    /// The ground of a dark face: the module material on a page, the sheet's cell colour in a sheet.
    @ViewBuilder
    private func darkGround(dense: Bool) -> some View {
        switch surface {
        case .sheet:
            HassTokens.Surface.sheetCell
        case .page:
            // The module's tint without a live blur (``ModuleBackground``).
            ModuleBackground.tint(dense ? .dense : .thin, reduceTransparency: reduceTransparency)
        }
    }

    /// A band from the leading edge as wide as ``level`` (or `default` when there is none).
    @ViewBuilder
    private func levelBand(default fallback: Double? = nil, @ViewBuilder fill: () -> some View) -> some View {
        if let level = level ?? fallback, level > 0 {
            let band = fill()
            GeometryReader { proxy in
                band.frame(width: proxy.size.width * min(1, level))
            }
        }
    }
}

// MARK: - Equal heights

private struct TileFillsHeightKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Whether tile faces stretch to the height their container offers (``View/equalHeightTiles()``).
    var tileFillsHeight: Bool {
        get { self[TileFillsHeightKey.self] }
        set { self[TileFillsHeightKey.self] = newValue }
    }
}

public extension View {
    /// Lets tiles inside fill the height a ``DynamicGridLayout`` with `equalRowHeights` gives them, so every tile in
    /// the grid matches the tallest (pattern: `.agents/patterns/dynamic-grid.md`).
    func equalHeightTiles() -> some View { environment(\.tileFillsHeight, true) }
}

/// Applies an identifier only when one is set.
private struct TileIdentifier: ViewModifier {
    var identifier: String?

    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}
