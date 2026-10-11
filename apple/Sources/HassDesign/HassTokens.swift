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
