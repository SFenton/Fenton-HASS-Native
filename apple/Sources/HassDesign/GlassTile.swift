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
    /// A solid fill the caller owns (`0xRRGGBB`, a room's ``RoomPalette`` colour): the tile draws white ink and a filled
    /// white glyph on it, on or off.
    public var fillRGB: UInt32?
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
    @Environment(\.valuesPending) private var valuesPending

    /// Creates a tile with a trailing accessory.
    public init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color? = nil,
        family: ColorFamily? = nil,
        fillRGB: UInt32? = nil,
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
        self.fillRGB = fillRGB
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
            fillRGB: fillRGB,
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
        // The first sign-in, before any value has arrived: the soft bar says nothing, so the tile does.
        if valuesPending, subtitle != nil || kind == .toggle { return "Loading" }
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
        fillRGB: UInt32? = nil,
        isActive: Bool,
        isUnavailable: Bool = false,
        isError: Bool = false,
        kind: Kind = .toggle,
        wash: Color? = nil,
        progress: Double? = nil,
        progressTint: Color? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint, family: family, fillRGB: fillRGB, isActive: isActive,
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
    /// A solid fill the caller owns (``RoomPalette``); wins over ``family``.
    var fillRGB: UInt32?
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
                fillRGB: UInt32? = nil, isActive: Bool, isUnavailable: Bool = false, isError: Bool = false, showsChevron: Bool = false,
                level: Double? = nil, levelTint: Color? = nil, wash: Color? = nil, trailingInset: CGFloat = 0) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.family = family
        self.fillRGB = fillRGB
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.tileLayout) private var preferredLayout
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.tileTitleLines) private var reservedTitleLines
    @Environment(\.tileFinish) private var preferredFinish
    @Environment(\.valuesPending) private var valuesPending
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .subheadline) private var titleLineHeight = TileMetrics.titleLineHeight
    @ScaledMetric(relativeTo: .title3) private var glyphHeight = TileMetrics.glyphHeight

    /// Light only for a tile in a sheet under the light scheme: pages are always dark.
    private var appearance: TileAppearance { .resolve(surface: surface, scheme: scheme) }

    /// The finish drawn: the environment's, or the solid one when the person asked for less transparency or more contrast
    /// (HIG, Accessibility), which keeps every ground opaque.
    private var finish: TileFinish {
        TileFinish.effective(preferredFinish, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
    }

    private var style: TileFaceStyle {
        .resolve(family: family, isActive: isActive, isError: isError, isUnavailable: isUnavailable, solidFill: fillRGB)
    }

    /// The arrangement drawn (``TileLayout``): the environment's, with a row turned into a bottom-anchored stack at
    /// accessibility text sizes.
    private var layout: TileLayout { preferredLayout.resolved(accessibilitySize: typeSize.isAccessibilitySize) }

    public var body: some View {
        let style = style
        let shape = RoundedRectangle(cornerRadius: finish.tokens(on: surface).cornerRadius, style: .continuous)
        let layout = layout
        content(style, layout)
            // The chevron is vertically centred on the tile in every arrangement (owner, 2026-10-16), so the text
            // keeps clear of it instead of running under.
            .padding(.trailing, showsChevron ? Self.chevronReserve : 0)
            .padding(.trailing, trailingInset)
            // Text wraps and the tile grows at large Dynamic Type instead of truncating. In an equal-height grid the face
            // also fills the row height it is offered.
            .frame(maxWidth: .infinity, minHeight: minContentHeight(layout), maxHeight: fillsHeight ? .infinity : nil,
                   alignment: layout == .stackedTop || layout == .anchoredBottom ? .topLeading : .leading)
            .padding(HassTokens.Spacing.m)
            .background { ground(style).clipShape(shape) }
            .overlay(alignment: .trailing) {
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(secondaryInk(style).opacity(0.8))
                        .padding(.trailing, HassTokens.Spacing.m)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if finish != .solid {
                    FrostedRim(finish: finish, style: style, surface: surface, appearance: appearance)
                }
            }
            .overlay {
                if style == .tinted {
                    shape.strokeBorder(tintGlyph.opacity(isEnabled ? 0.5 : 0.25), lineWidth: 1)
                        .opacity(isUnavailable ? 0.5 : 1)
                }
            }
            .contentShape(shape)
    }

    /// The content height the tile keeps: the layout's minimum, or room for the reserved title lines at this text size.
    private func minContentHeight(_ layout: TileLayout) -> CGFloat {
        TileMetrics.minContentHeight(layout: layout, titleLines: reservedTitleLines, glyphHeight: glyphHeight,
                                     titleLineHeight: titleLineHeight)
    }

    /// Width the text keeps clear for the centred chevron: its glyph plus the gap before it.
    static let chevronReserve: CGFloat = 20

    // MARK: Layouts

    /// The glyph: decorative, because the title names the tile. Symbols carry built-in labels ("Humidifier"), which the
    /// audit then flagged as clipped text on iPad (glyph wider than its frame).
    @ViewBuilder
    private func glyph(_ style: TileFaceStyle, layout: TileLayout) -> some View {
        if finish.usesGlyphDisc {
            discGlyph(style)
        } else {
            plainGlyph(style, layout: layout)
        }
    }

    /// Finish B: the glyph sits on a disc that carries the family colour, so the tile itself can stay one neutral module.
    private func discGlyph(_ style: TileFaceStyle) -> some View {
        let fill: Color = switch style {
        case let .filled(family): family.fill ?? Color(rgb: family.spec.glyph)
        case let .colored(rgb): Color(rgb: rgb)
        case .lit: LitTile.bandBottom
        case .error: Color(rgb: appearance.errorRGB).opacity(0.2)
        case .off, .tinted: Color.black.opacity(appearance == .light ? TileFinish.offDiscShade.light : TileFinish.offDiscShade.dark)
        }
        let ink: Color = switch style {
        case let .filled(family): family.ink
        case .colored: RoomPalette.ink
        case .lit: LitTile.glyph
        default: glyphColor(style)
        }
        return Image(systemName: symbol)
            .font(.body)
            .symbolVariant(isActive || style.isColored ? .fill : .none)
            .foregroundStyle(ink)
            .frame(width: Self.discDiameter, height: Self.discDiameter)
            .background(fill, in: Circle())
            .opacity(isUnavailable ? 0.5 : 1)
            .accessibilityHidden(true)
    }

    /// The glyph disc's diameter under finish B: 34 pt, which also fixes the row layout's glyph column.
    static let discDiameter: CGFloat = 34

    private func plainGlyph(_ style: TileFaceStyle, layout: TileLayout) -> some View {
        Image(systemName: symbol)
            .font(layout == .row ? .title2 : .title3)
            // Filled for an active tile and for a coloured navigation tile; an off tile keeps the outline.
            .symbolVariant(isActive || style.isColored ? .fill : .none)
            .foregroundStyle(glyphColor(style))
            // Unavailable dims the glyph and the tinted stroke only. The title and "Unavailable" keep 4.5:1
            // and the ground stays full strength, so wallpaper never shows through behind white text: a
            // whole-face fade left the text at 2.4:1 (signed-in Security tab before states arrived, 2026-10-14).
            .opacity(isUnavailable ? 0.5 : 1)
            .accessibilityHidden(true)
    }

    private func text(_ style: TileFaceStyle, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryInk(style))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if subtitle != nil, valuesPending {
                // The first sign-in, before any value has arrived: the name is real, the value is a soft bar.
                PendingValueBar()
            } else if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(secondaryInk(style))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(FinishTextShadow(finish: finish, surface: surface))
    }

    @ViewBuilder
    private func content(_ style: TileFaceStyle, _ layout: TileLayout) -> some View {
        switch layout {
        case .row:
            HStack(alignment: .center, spacing: HassTokens.Spacing.m) {
                glyph(style, layout: layout)
                    .frame(width: finish.usesGlyphDisc ? Self.discDiameter : Self.rowGlyphWidth)
                text(style, spacing: 2)
            }
        case .anchoredBottom:
            // No stack spacing: the spacer's minimum is the whole gap, so the height reserved for the glyph, the gap and
            // the title lines (``TileMetrics``) is the height drawn.
            VStack(alignment: .leading, spacing: 0) {
                glyph(style, layout: layout)
                Spacer(minLength: TileMetrics.glyphGap)
                text(style, spacing: 2)
            }
        case .centeredStack:
            VStack(alignment: .leading, spacing: HassTokens.Spacing.xs) {
                glyph(style, layout: layout)
                text(style, spacing: 2)
            }
        case .stackedTop:
            VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                glyph(style, layout: layout)
                text(style, spacing: HassTokens.Spacing.s)
            }
        }
    }

    /// The row layout's glyph column: wide enough for the widest symbol so every title starts at the same x.
    static let rowGlyphWidth: CGFloat = 30

    // MARK: Ink

    // The lit tile and the family fills are fixed grounds with fixed inks, in every appearance. The off, tinted and error
    // faces sit on a dark module (pages) or the sheet's cell, which is white in a light sheet: their inks follow
    // ``appearance`` (a light-appearance gallery once drew black titles on the dark ground, 2.7:1).

    /// A grey for glyphs and chevrons that carry no meaning of their own.
    private var muted: Color {
        appearance == .light ? HassTokens.Surface.secondaryInSheet : HassTokens.Surface.secondaryOnModule
    }

    /// The caller's tint as a glyph on the face: unchanged on dark, darkened to 3:1 on a light cell.
    private var tintGlyph: Color {
        guard appearance == .light else { return tint }
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        let resolved = tint.resolve(in: environment)
        let shaded = TileFaceStyle.lightGlyph(forTint: (Double(resolved.red), Double(resolved.green), Double(resolved.blue)))
        return Color(.sRGB, red: shaded.red, green: shaded.green, blue: shaded.blue, opacity: Double(resolved.opacity))
    }

    private func glyphColor(_ style: TileFaceStyle) -> Color {
        switch style {
        case .off:
            isEnabled ? (family.map { family in
                finish == .solid ? family.offGlyph : Color(rgb: family.offGlyphRGB(appearance.scheme, keep: finish.offGlyphKeep))
            } ?? muted) : muted
        case .lit: LitTile.glyph
        case let .filled(family): family.ink
        case .colored: RoomPalette.ink
        case .tinted: isEnabled ? tintGlyph : muted
        case .error: Color(rgb: appearance.errorRGB)
        }
    }

    /// The style whose inks the text takes: finish B keeps the module neutral, so its text is the off face's (white, or the
    /// label colour in a light sheet) whatever the state; an error keeps its red.
    private func inkStyle(_ style: TileFaceStyle) -> TileFaceStyle {
        finish.usesGlyphDisc && style != .error ? .off : style
    }

    private func primaryInk(_ style: TileFaceStyle) -> Color {
        switch inkStyle(style) {
        case .lit: LitTile.ink
        case let .filled(family): family.ink
        case .colored: RoomPalette.ink
        default: appearance == .light ? HassTokens.Ink.primary : .white
        }
    }

    private func secondaryInk(_ style: TileFaceStyle) -> Color {
        switch inkStyle(style) {
        case .lit: LitTile.secondaryInk
        case let .filled(family): family.secondaryInk
        case .colored: RoomPalette.ink
        case .error: Color(rgb: appearance.errorRGB)
        // A state wash lifts the dark ground toward its colour, and over a bright sky the 68% ink fell to 4.3:1
        // (folded Duo Quick Links: Armed Home and the food tile, 2026-10-14). On a light cell the wash is faint
        // (``TileAppearance/washOpacity``) and the label colour at 72% holds 4.5:1 over it.
        default:
            if appearance == .light { wash != nil ? HassTokens.Ink.secondary : HassTokens.Surface.secondaryInSheet }
            else if wash != nil { HassTokens.Surface.secondaryOnWash }
            // A frosted ground is a little lighter than the thin module, so its state text takes the denser wallpaper ink.
            else if finish != .solid, surface == .page { HassTokens.Surface.secondaryOnWallpaper }
            else { HassTokens.Surface.secondaryOnModule }
        }
    }

    // MARK: Ground

    @ViewBuilder
    private func ground(_ style: TileFaceStyle) -> some View {
        if finish == .solid {
            solidGround(style)
        } else {
            FrostedGround(finish: finish, style: style, surface: surface, appearance: appearance, tint: tint, wash: wash,
                          level: level, levelTint: levelTint)
        }
    }

    @ViewBuilder
    private func solidGround(_ style: TileFaceStyle) -> some View {
        switch style {
        case .off, .tinted, .error:
            ZStack(alignment: .leading) {
                darkGround(dense: style == .error)
                if let wash { wash.opacity(appearance.washOpacity) }
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
        case let .colored(rgb):
            // Flat, with no top highlight: the white ink is measured against the fill itself (4.7:1 or better).
            Color(rgb: rgb)
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
