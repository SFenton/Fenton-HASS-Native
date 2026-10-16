import SwiftUI

public extension Color {
    /// A colour from `0xRRGGBB` sRGB (public so feature code can use ``HassTokens/Palette`` values).
    init(rgb: UInt32) {
        let (red, green, blue) = Self.components(rgb)
        self.init(.sRGB, red: red, green: green, blue: blue)
    }

    /// The red, green and blue channels of `0xRRGGBB`, from 0 to 1.
    internal static func components(_ rgb: UInt32) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }
}
