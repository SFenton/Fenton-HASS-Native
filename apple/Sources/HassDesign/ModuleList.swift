import SwiftUI

// MARK: - List

/// An inset list on the wallpaper (`.agents/design/direction-g.md`, Controls: Lists): rows on one
/// ``SwiftUICore/View/module(_:cornerRadius:)`` card with hairlines inset to the text, like an inset grouped list
/// on a page. Sheets use the system `Form` where they can, whose grouped colours are G's sheet ground and cells;
/// a sheet that can't be a `Form` (a map, a bottom section bar) gets the same look from this list, which draws its
/// rows on the sheet's cell (`#2C2C2E` dark, white light, ``HassTokens/Surface/sheetCell``) when
/// ``SwiftUICore/EnvironmentValues/tileSurface`` is `.sheet` (`modalChrome()` sets it), with the title and secondary
/// ink and the hairlines of the sheet's appearance.
///
/// On iOS 18 and later the list draws a hairline between rows; iOS 17 has no API to visit a view builder's rows,
/// so rows there sit flush with no hairline (the deployment target, not a device Stephen uses).
public struct ModuleList<Content: View>: View {
    private let density: ModuleDensity
    private let hasGlyphs: Bool
    private let content: Content
    @Environment(\.tileSurface) private var surface
    /// Where hairlines start: past the row's leading glyph, at its text.
    @ScaledMetric(relativeTo: .body) private var textInset: CGFloat = ModuleRowMetrics.textInset

    /// Creates a list.
    /// - Parameters:
    ///   - density: ``ModuleDensity/thin`` (default), or ``ModuleDensity/dense`` when a row carries red or orange text.
    ///   - hasGlyphs: Whether rows lead with a glyph. Hairlines start at the text: past the glyph column (default), or
    ///     at the row's 16 pt margin for rows of text alone (steps, facts).
    ///   - content: The rows, usually ``ModuleRow``s.
    public init(_ density: ModuleDensity = .thin, hasGlyphs: Bool = true, @ViewBuilder content: () -> Content) {
        self.density = density
        self.hasGlyphs = hasGlyphs
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.module, style: .continuous)
        if surface == .sheet {
            rows
                .frame(maxWidth: .infinity)
                .background(HassTokens.Surface.sheetCell, in: shape)
                .clipShape(shape)
        } else {
            rows
                .frame(maxWidth: .infinity)
                .module(density)
                .clipShape(shape)
        }
    }

    @ViewBuilder
    private var rows: some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) {
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        if subview.id != subviews.first?.id {
                            HassTokens.Surface.separator
                                .frame(height: 0.5)
                                .padding(.leading, hasGlyphs ? textInset : HassTokens.Spacing.l)
                                .accessibilityHidden(true)
                        }
                        subview
                    }
                }
            }
        } else {
            VStack(spacing: 0) { content }
        }
    }
}

// MARK: - List row background

/// A module's share of one row, for a real `List` whose rows need system swipe actions (a `ScrollView` can't have them
/// before iOS 27): the density's tint with the module's corners rounded on the first row's top and the last row's bottom,
/// so the rows read as one inset card (`.listRowBackground(ModuleRowBackground(...))`). Pair it with
/// ``SwiftUICore/View/moduleRowSeparator(isFirst:inset:)`` for the hairline.
public struct ModuleRowBackground: View {
    private let density: ModuleDensity
    private let isFirst: Bool
    private let isLast: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Creates a row background.
    /// - Parameters:
    ///   - density: The module's density.
    ///   - isFirst: The row is the first of its card (top corners rounded).
    ///   - isLast: The row is the last of its card (bottom corners rounded).
    public init(_ density: ModuleDensity = .thin, isFirst: Bool, isLast: Bool) {
        self.density = density
        self.isFirst = isFirst
        self.isLast = isLast
    }

    public var body: some View {
        let radius = HassTokens.Radius.module
        // The shape is the fill, not a clip over a square one: a clip is a mask layer, which the render server draws in an
        // offscreen pass for every row on screen, on every frame of a scroll.
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0, bottomLeadingRadius: isLast ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0, topTrailingRadius: isFirst ? radius : 0, style: .continuous
        )
        .fill(ModuleBackground.tint(density, reduceTransparency: reduceTransparency))
    }
}

public extension View {
    /// Draws the hairline above a row that isn't the first of its ``ModuleRowBackground`` card, inset to the row's text.
    /// Use with `.listRowSeparator(.hidden)`: the system separator can't be inset per row in a plain card.
    /// - Parameters:
    ///   - isFirst: The row is the first of its card, so it has no hairline above it.
    ///   - inset: Where the hairline starts; defaults to ``ModuleRowMetrics/textInset``.
    func moduleRowSeparator(isFirst: Bool, inset: CGFloat = ModuleRowMetrics.textInset) -> some View {
        overlay(alignment: .top) {
            if !isFirst {
                HassTokens.Surface.separator
                    .frame(height: 0.5)
                    .padding(.leading, inset)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Row

/// One row of a ``ModuleList``: a leading glyph in its colour family, a title and optional subtitle, then a trailing
/// accessory (a value, a state capsule, a pop-up menu) and a chevron when the row opens something. 52 pt tall, 60 pt
/// with a subtitle. At accessibility text sizes the accessory moves under the text so neither truncates.
///
/// Pure drawing: wrap it in a `Button` (with ``ModuleRowButtonStyle``) or give it a control as its accessory. On a
/// page the inks are fixed white because the wallpaper is always dark; in a sheet (``SwiftUICore/EnvironmentValues/tileSurface``)
/// they follow the sheet's appearance.
public struct ModuleRow<Accessory: View>: View {
    private let symbol: String?
    private let glyph: Color?
    private let title: String
    private let subtitle: String?
    private let subtitleInk: Color?
    private let showsChevron: Bool
    private let glyphOpacity: Double
    private let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.tileSurface) private var surface
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = ModuleRowMetrics.glyphWidth

    /// Creates a row.
    /// - Parameters:
    ///   - title: The row's name.
    ///   - subtitle: An optional second line (a state, or what the row opens).
    ///   - symbol: The leading SF Symbol, or nil for none.
    ///   - glyph: The symbol's colour; a family's glyph, or nil for the row's secondary ink (neutral rows).
    ///   - subtitleInk: Overrides the subtitle's secondary ink (a red error on a dense list).
    ///   - glyphOpacity: Dims only the glyph (unavailable rows keep their text at full contrast).
    ///   - showsChevron: Draws a trailing chevron: the row opens something.
    ///   - accessory: Trailing content.
    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil,
                glyph: Color? = nil, subtitleInk: Color? = nil, glyphOpacity: Double = 1,
                showsChevron: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.glyph = glyph
        self.subtitleInk = subtitleInk
        self.glyphOpacity = glyphOpacity
        self.showsChevron = showsChevron
        self.accessory = accessory()
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
                    HStack(spacing: ModuleRowMetrics.gap) { leading; chevron }
                    accessory
                }
            } else {
                HStack(spacing: ModuleRowMetrics.gap) {
                    leading
                    accessory
                    chevron
                }
            }
        }
        .padding(.horizontal, HassTokens.Spacing.l)
        .padding(.vertical, HassTokens.Spacing.s)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 52 : 60, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var leading: some View {
        HStack(spacing: ModuleRowMetrics.gap) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .stateForeground("ModuleRow", glyph ?? secondaryInk)
                    .opacity(glyphOpacity)
                    .frame(width: glyphWidth)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(surface == .sheet ? HassTokens.Ink.primary : .white)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .stateForeground("ModuleRow", subtitleInk ?? secondaryInk)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Title and subtitle read as one element ("Thermostat Hub, Heat"), apart from the accessory's control.
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(secondaryInk)
                .accessibilityHidden(true)
        }
    }

    /// Secondary text and neutral glyphs: the module's on a page, the sheet's in a sheet.
    private var secondaryInk: Color {
        surface == .sheet ? HassTokens.Surface.secondaryInSheet : HassTokens.Surface.secondaryOnModule
    }
}

public extension ModuleRow where Accessory == EmptyView {
    /// Creates a row with no accessory.
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil,
         glyph: Color? = nil, subtitleInk: Color? = nil, glyphOpacity: Double = 1,
         showsChevron: Bool = false) {
        self.init(title, subtitle: subtitle, symbol: symbol, glyph: glyph, subtitleInk: subtitleInk,
                  glyphOpacity: glyphOpacity, showsChevron: showsChevron) { EmptyView() }
    }
}

/// Measurements shared by ``ModuleRow`` and the hairlines of ``ModuleList``. Public so a feature row that can't be a
/// ``ModuleRow`` (a tinted title, a toggle glyph) lines up with the hairlines without repeating the numbers.
public enum ModuleRowMetrics {
    /// Width of the leading glyph column.
    public static let glyphWidth: CGFloat = 24
    /// Space between the glyph, the text and the accessory.
    public static let gap: CGFloat = 14
    /// Leading edge of the text, where hairlines start: padding, glyph and gap.
    public static let textInset: CGFloat = HassTokens.Spacing.l + glyphWidth + gap
}

// MARK: - Button style

/// Presses a ``ModuleRow`` like a list cell: a light highlight across the row while held. Never fades a disabled
/// row's text (see ``GlassTileButtonStyle``); rows dim their glyph instead.
public struct ModuleRowButtonStyle: ButtonStyle {
    /// Creates the style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // White on a page and in a dark sheet, black in a light one: the label colour at 10%.
            // Down at once, released with `quick` (`.agents/design/motion-components.md`).
            .background {
                Rectangle().fill(HassTokens.Ink.primary.opacity(configuration.isPressed ? 0.10 : 0))
                    .quickTransition("ModuleRowButtonStyle", value: configuration.isPressed, instant: configuration.isPressed)
            }
    }
}

#Preview("Module list") {
    VStack(spacing: 16) {
        ModuleList {
            ModuleRow("Front Door", symbol: "lock") { Text("Locked").foregroundStyle(.white) }
            ModuleRow("Left Door", symbol: "door.garage.closed") { Text("Closed").foregroundStyle(.white) }
            ModuleRow("Room Thermostats", subtitle: "View each room's temperature.", symbol: "house", showsChevron: true)
        }
    }
    .padding()
    .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom))
}
