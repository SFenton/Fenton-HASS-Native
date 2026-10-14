import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Design tokens shared by every Apple surface. Values follow the web dashboard's density
/// (`src/styles/tokens.css`) adapted to HIG spacing.
public enum HassTokens {
    // MARK: - Spacing

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    // MARK: - Radii

    public enum Radius {
        /// Tiles (direction G, Controls: 22 pt).
        public static let tile: CGFloat = 22
        /// Modules, cards and inset lists on the wallpaper (direction G, Layers: 26 pt).
        public static let module: CGFloat = 26
        public static let chip: CGFloat = 16
        public static let media: CGFloat = 16
    }

    // MARK: - State colors

    /// Tints for active entity states, from the web's card colors.
    public enum Tint {
        public static let light = Color(red: 1.0, green: 0.78, blue: 0.29)
        public static let security = Color(red: 0.90, green: 0.22, blue: 0.21)
        public static let climate = Color(red: 0.10, green: 0.33, blue: 0.51)
        public static let presence = Color(red: 0.20, green: 0.76, blue: 0.57)
        public static let contact = Color(red: 0.98, green: 0.55, blue: 0.20)
        public static let neutral = Color.secondary
        /// Water (sprinklers); dark enough for white text at 4.5:1.
        public static let water = Color(red: 0.05, green: 0.40, blue: 0.70)
    }

    // MARK: - Direction G palette

    /// Direction G's fixed colours as `0xRRGGBB` sRGB, kept raw so tests can check contrast
    /// (`.agents/design/direction-g.md`, Colour). Views use the `Color`s on ``Ink`` and ``Surface``.
    public enum Palette {
        /// Tint for text and glyph actions on dark (system blue lifted for small text; `#007AFF` and `#0A84FF`
        /// fail 4.5:1 on dark).
        public static let tintText: UInt32 = 0x409CFF
        /// Tint for filled controls with a white label (``PrimaryButton``, the sheet confirm check).
        public static let tintFill: UInt32 = 0x0071E3
        /// Destructive, error and overdue text and glyphs on dark.
        public static let red: UInt32 = 0xFF6961
        /// Soon and warning text and glyphs on dark.
        public static let orange: UInt32 = 0xFFB340
        /// Count badges (Chores overdue), under white numerals.
        public static let badge: UInt32 = 0xD93025
        /// Sheet ground in dark appearance (`systemGray6` dark).
        public static let sheetGround: UInt32 = 0x1C1C1E
        /// Cells and tiles inside a sheet (`systemGray5` dark).
        public static let sheetCell: UInt32 = 0x2C2C2E
        /// The thin module on the wallpaper: `#1C1C1E` at 66% (G's 55% over a background blur, without the live blur
        /// the pre-blurred wallpaper makes redundant).
        public static let moduleThin: UInt32 = 0x1C1C1E
        /// The dense module that carries red or orange text over the lit windows: `#141416` at 78%.
        public static let moduleDense: UInt32 = 0x141416
        /// Secondary label: `rgba(235,235,245,.68)` on modules and `.6` in sheets.
        public static let secondaryLabel: UInt32 = 0xEBEBF5
    }

    // MARK: - Text

    /// Text colors for content on materials. Plain `Color`s rather than the hierarchical `.primary` /
    /// `.secondary` styles, which pick up vibrancy on a material and fail the contrast audit there.
    public enum Ink {
        /// Titles and values.
        public static let primary = label
        /// Supporting text (summaries, states): still at least 4.5:1 on the light and dark materials.
        public static let secondary = label.opacity(0.72)

        /// Text on an always-dark backdrop (the weather card and sheet gradients): white, at least 5.6:1 on the
        /// lightest backdrop color, in light and dark mode alike.
        public static let onDark = Color.white
        /// Supporting text on an always-dark backdrop: white at 85%, at least 4.5:1 on the lightest backdrop color.
        public static let onDarkSecondary = Color.white.opacity(0.85)

        /// Inline error text (``InlineAlert`` error severity): a red dark enough for 4.5:1 on light materials and
        /// light enough on dark ones (tuned on the Vacation and Solo Trip pages).
        public static let error: Color = dynamic(light: (0.70, 0.11, 0.11), dark: Palette.red)

        /// Destructive actions ("Stop watering"): system red is 3.6:1 on a light grouped row, this is at least
        /// 6:1 on light rows and G's `#FF6961` on dark (HIG: Color; WCAG 1.4.3).
        public static let danger: Color = dynamic(light: (0.76, 0.09, 0.09), dark: Palette.red)

        /// Soon and warning text ("Due Tomorrow"): G's `#FFB340` on dark, a dark amber at 4.5:1 or better on light.
        public static let warning: Color = dynamic(light: (0.60, 0.33, 0.0), dark: Palette.orange)

        /// Tint for text buttons, links and glyph actions: 5.6:1 on light rows, and G's `#409CFF` on dark.
        public static let action: Color = dynamic(light: (0.0, 0.40, 0.80), dark: Palette.tintText)

        /// Fill for controls with a white label (``PrimaryButton``, the sheet confirm check): G's `#0071E3`, 4.6:1
        /// under white in both appearances.
        public static let actionFill = Color(rgb: Palette.tintFill)

        /// Count badges under white numerals: `#D93025`.
        public static let badge = Color(rgb: Palette.badge)

        /// A color with light and dark `0xRRGGBB` variants.
        private static func dynamic(light: (Double, Double, Double), dark: UInt32) -> Color {
            dynamic(light: light, dark: Color.components(dark))
        }

        /// A color with light and dark variants (watchOS is always dark).
        private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
            #if os(iOS)
            Color(uiColor: UIColor { traits in
                let rgb = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            })
            #elseif os(macOS)
            Color(nsColor: NSColor(name: nil) { appearance in
                let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            })
            #else
            Color(red: dark.0, green: dark.1, blue: dark.2)
            #endif
        }

        /// The platform label color as a plain dynamic color (`Color.primary` resolves to the vibrant
        /// hierarchical style inside a material).
        private static var label: Color {
            #if canImport(UIKit)
            Color(uiColor: .label)
            #else
            Color(nsColor: .labelColor)
            #endif
        }
    }

    // MARK: - Surfaces

    /// Direction G's grounds (`.agents/design/direction-g.md`, Layers). Pages are always dark on the wallpaper.
    public enum Surface {
        /// Sheet ground, dark appearance.
        public static let sheetGround = Color(rgb: Palette.sheetGround)
        /// Cells and tiles inside a sheet.
        public static let sheetCell = Color(rgb: Palette.sheetCell)
        /// The thin module tint (``SwiftUICore/View/module(_:cornerRadius:)``).
        public static let moduleThin = Color(rgb: Palette.moduleThin).opacity(0.66)
        /// The dense module for red and orange text; also the opaque-enough fallback with Reduce Transparency.
        public static let moduleDense = Color(rgb: Palette.moduleDense).opacity(0.78)
        /// Hairline separators on dark: white at 14%.
        public static let separator = Color.white.opacity(0.14)
        /// Secondary labels on modules.
        public static let secondaryOnModule = Color(rgb: Palette.secondaryLabel).opacity(0.68)
        /// Secondary labels in sheets.
        public static let secondaryInSheet = Color(rgb: Palette.secondaryLabel).opacity(0.6)
    }

    /// Minimum hit target (HIG: Buttons).
    public static let minTarget: CGFloat = 44
}
