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
        /// Tiles and cards (web Quick Links use 32 px corners; tiles here use the HIG-friendly 20 pt).
        public static let tile: CGFloat = 20
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

        /// Destructive actions ("Stop watering"): system red is 3.6:1 on a light grouped row, this is at least
        /// 6:1 on light and dark rows (HIG: Color; WCAG 1.4.3).
        public static let danger: Color = dynamic(light: (0.76, 0.09, 0.09), dark: (1.0, 0.45, 0.43))

        /// Tint for buttons and links on these pages: the app's light-blue accent is about 2.5:1 as text on a light
        /// row and under white text on a filled button. This is 5.6:1 in light mode and system blue in dark mode.
        public static let action: Color = dynamic(light: (0.0, 0.40, 0.80), dark: (0.04, 0.52, 1.0))

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

    /// Minimum hit target (HIG: Buttons).
    public static let minTarget: CGFloat = 44
}
