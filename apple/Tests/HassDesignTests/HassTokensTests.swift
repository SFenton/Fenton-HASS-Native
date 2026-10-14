import Foundation
@testable import HassDesign
import Testing

/// Direction G's palette against WCAG 1.4.3 (text 4.5:1) on the grounds it is drawn on.
struct HassTokensTests {
    typealias Palette = HassTokens.Palette

    private func luminance(_ rgb: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The darkest and lightest grounds G text sits on: sheet ground, sheet cells, and the dense module.
    private static let darkGrounds: [UInt32] = [Palette.sheetGround, Palette.sheetCell, Palette.moduleDense]

    @Test(arguments: darkGrounds)
    func tintRedAndOrangeReadOnDarkGrounds(_ ground: UInt32) {
        #expect(contrast(Palette.tintText, ground) >= 4.5, "tint")
        #expect(contrast(Palette.red, ground) >= 4.5, "red")
        #expect(contrast(Palette.orange, ground) >= 4.5, "orange")
    }

    @Test func whiteLabelsReadOnFilledTintAndBadge() {
        #expect(contrast(0xFFFFFF, Palette.tintFill) >= 4.5)
        #expect(contrast(0xFFFFFF, Palette.badge) >= 4.5)
    }

    @Test func systemBlueFailsWhereTheLiftedTintPasses() {
        // Why G lifts the tint: system blue as small text on a sheet cell is below 4.5:1.
        #expect(contrast(0x0A84FF, Palette.sheetCell) < 4.5)
        #expect(contrast(Palette.tintText, Palette.sheetCell) >= 4.5)
    }

    @Test func radiiMatchDirectionG() {
        #expect(HassTokens.Radius.tile == 22)
        #expect(HassTokens.Radius.module == 26)
    }
}
