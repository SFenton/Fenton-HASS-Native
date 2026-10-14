import Foundation
@testable import HassDesign
import SwiftUI
import Testing

struct ColorFamilyTests {
    /// WCAG relative luminance of `0xRRGGBB`.
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

    @Test(arguments: ColorFamily.allCases)
    func inkOnFillPassesBodyContrast(_ family: ColorFamily) {
        guard let fill = family.spec.fill else { return }
        let ink: UInt32 = family.spec.darkInk ? 0x1C1C1E : 0xFFFFFF
        // Supporting text is white at 92% (or dark olive at 82%) over the fill.
        let secondary = family.spec.darkInk
            ? ColorFamily.mix(0x282000, fill, 0.82)
            : ColorFamily.mix(0xFFFFFF, fill, 0.92)
        #expect(contrast(ink, fill) >= 4.5, "\(family) title")
        #expect(contrast(secondary, fill) >= 4.5, "\(family) subtitle")
    }

    @Test(arguments: ColorFamily.allCases)
    func glyphIsVisibleOnASheetTile(_ family: ColorFamily) {
        // Non-text contrast (WCAG 1.4.11) against the sheet's tile colour, #2C2C2E.
        #expect(contrast(family.spec.glyph, 0x2C2C2E) >= 3, "\(family)")
    }

    @Test func onlyLightsAndNeutralAreNeverFilled() {
        let unfilled = ColorFamily.allCases.filter { $0.spec.fill == nil }
        #expect(Set(unfilled) == [.lights, .neutral])
    }

    @Test func mixBlendsEachChannel() {
        #expect(ColorFamily.mix(0xFFFFFF, 0x000000, 1) == 0xFFFFFF)
        #expect(ColorFamily.mix(0xFFFFFF, 0x000000, 0) == 0x000000)
        #expect(ColorFamily.mix(0xFF0000, 0x0000FF, 0.5) == 0x800080)
    }
}

struct ArcSpinnerTests {
    @Test func turnsOncePerPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(ArcSpinner.angle(at: start, reduceMotion: false) == 0)
        let quarter = Date(timeIntervalSinceReferenceDate: ArcSpinner.period / 4)
        #expect(abs(ArcSpinner.angle(at: quarter, reduceMotion: false) - 90) < 0.001)
    }

    @Test func reduceMotionHalvesTheSpeed() {
        let quarter = Date(timeIntervalSinceReferenceDate: ArcSpinner.period / 4)
        #expect(abs(ArcSpinner.angle(at: quarter, reduceMotion: true) - 45) < 0.001)
    }
}
